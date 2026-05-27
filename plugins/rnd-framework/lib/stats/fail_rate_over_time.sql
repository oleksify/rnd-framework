-- FAIL-rate over time (drift): verifier-FAIL rate bucketed by ISO week,
-- split by segment. Surfaces whether verification quality is drifting up or
-- down across the project's history.
--
-- Verdicts and their timestamps come from per-slug calibration.jsonl; the
-- segment is derived DIRECTLY from the calibration filename's slug (first path
-- component) — no session join is needed. Correction records carry no verdict
-- and are excluded.
--
-- calibration.jsonl is read as RAW physical lines (one VARCHAR per line), then
-- filtered with json_valid and projected with TRY(json_extract_string(...)).
-- This tolerates malformed/truncated legacy files: read_json_auto aborts the
-- whole scan on the first bad line in any matched file (ignore_errors does not
-- help with truncated newline_delimited JSON), whereas the raw-line read skips
-- only the bad lines. The TRY wrapper is load-bearing: json_extract_string
-- THROWS on a malformed fragment and the optimizer may run the projection on
-- rows the json_valid filter would discard, so TRY returns NULL instead of
-- aborting. The timestamp string is CAST to TIMESTAMP after extraction.
--
-- Run from the .rnd root (the directory whose children are slug dirs):
--   duckdb -c ".read lib/stats/fail_rate_over_time.sql" -c "SELECT * FROM fail_rate_over_time ORDER BY segment, week"

CREATE OR REPLACE VIEW fail_rate_over_time AS
WITH
  -- Dogfood allowlist: a source slug in this list is the rnd-framework repo
  -- instrumenting itself; everything else is a downstream feature project.
  dogfood_slugs AS (
    SELECT unnest(['claude-130cb64f']) AS slug
  ),

  -- Per-slug calibration: slug is the first path component of the filename.
  verdicts AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1)             AS slug,
      TRY(json_extract_string(j, '$.verdict'))                  AS verdict,
      CAST(TRY(json_extract_string(j, '$.timestamp')) AS TIMESTAMP) AS ts
    FROM read_csv(
      '*/calibration.jsonl',
      columns = {'j': 'VARCHAR'},
      delim = E'\x01',
      quote = '', escape = '',
      header = false,
      auto_detect = false,
      ignore_errors = true,
      filename = true
    )
    WHERE json_valid(j)
      AND TRY(json_extract_string(j, '$.verdict')) IS NOT NULL  -- drop correction records (they carry no verdict)
  ),

  classified AS (
    SELECT
      CASE WHEN slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment,
      date_trunc('week', ts)                 AS week,
      verdict
    FROM verdicts
  )

SELECT
  segment,
  week,
  count(*)                                              AS task_count,
  count(*) FILTER (WHERE verdict = 'FAIL')              AS fail_count,
  round(count(*) FILTER (WHERE verdict = 'FAIL') * 1.0 / count(*), 4) AS fail_rate
FROM classified
GROUP BY ALL;
