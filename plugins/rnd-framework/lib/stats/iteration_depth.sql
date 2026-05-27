-- Iteration-depth distribution: histogram of how many build-verify cycles
-- tasks needed, split by segment. iterationCount lives directly on each
-- calibration verdict record; correction records carry no verdict and are
-- excluded.
--
-- Segment is derived DIRECTLY from the per-slug calibration filename — no
-- session join is needed.
--
-- calibration.jsonl is read as RAW physical lines (one VARCHAR per line), then
-- filtered with json_valid and projected with TRY(json_extract_string(...)).
-- This tolerates malformed/truncated legacy files: read_json_auto aborts the
-- whole scan on the first bad line in any matched file (ignore_errors does not
-- help with truncated newline_delimited JSON), whereas the raw-line read skips
-- only the bad lines. The TRY wrapper is load-bearing: json_extract_string
-- THROWS on a malformed fragment and the optimizer may run the projection on
-- rows the json_valid filter would discard, so TRY returns NULL instead of
-- aborting. iterationCount is CAST to INTEGER after extraction.
--
-- Run from the .rnd root (the directory whose children are slug dirs):
--   duckdb -c ".read lib/stats/iteration_depth.sql" -c "SELECT * FROM iteration_depth ORDER BY segment, iteration_count"

CREATE OR REPLACE VIEW iteration_depth AS
WITH
  -- Dogfood allowlist: a source slug in this list is the rnd-framework repo
  -- instrumenting itself; everything else is a downstream feature project.
  dogfood_slugs AS (
    SELECT unnest(['claude-130cb64f']) AS slug
  ),

  -- Per-slug calibration: slug is the first path component of the filename.
  verdicts AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1)                    AS slug,
      CAST(TRY(json_extract_string(j, '$.iterationCount')) AS INTEGER) AS iteration_count
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
      iteration_count
    FROM verdicts
  )

SELECT
  segment,
  iteration_count,
  count(*) AS task_count
FROM classified
GROUP BY ALL;
