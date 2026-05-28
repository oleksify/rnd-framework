-- Per-shape verifier-FAIL rate: for each (segment, shape), the fraction of
-- tasks whose verifier verdict was FAIL.
--
-- Verdicts come from per-slug calibration.jsonl files; the segment is derived
-- DIRECTLY from the calibration filename's slug (first path component) — no
-- session join is needed because calibration is per-slug. The shape dimension
-- comes from the audit (session, assertion) facts, joined on taskId.
-- Correction records (correction field, no verdict) are excluded.
--
-- Both audit.jsonl and calibration.jsonl are read as RAW physical lines (one
-- VARCHAR per line), then filtered with json_valid and projected with
-- TRY(json_extract_string(...)). This tolerates malformed/truncated legacy
-- files: read_json_auto aborts the whole scan on the first bad line in any
-- matched file (ignore_errors does not help with truncated newline_delimited
-- JSON), whereas the raw-line read skips only the bad lines. The TRY wrapper is
-- load-bearing: json_extract_string THROWS on a malformed fragment and the
-- optimizer may run the projection on rows the json_valid filter would discard,
-- so TRY returns NULL instead of aborting. json_extract_string also returns NULL
-- for absent keys, reproducing the old union_by_name NULL-fill.
--
-- Run from the .rnd root (the directory whose children are slug dirs):
--   duckdb -c ".read lib/stats/per_shape_fail_rate.sql" -c "SELECT * FROM per_shape_fail_rate ORDER BY segment, shape"

CREATE OR REPLACE VIEW per_shape_fail_rate AS
WITH
  -- Dogfood allowlist: comma-separated slug list via the RND_DOGFOOD_SLUGS
  -- env var (a slug in this list is the rnd-framework repo instrumenting
  -- itself; empty/unset → everything classifies as feature). The env var is
  -- the single source of truth — see commands/rnd-stats.md for the default.
  dogfood_slugs AS (
    SELECT trim(s) AS slug
    FROM (
      SELECT unnest(string_split(COALESCE(getenv('RND_DOGFOOD_SLUGS'), ''), ',')) AS s
    ) t
    WHERE trim(s) != ''
  ),

  -- Single recursive glob matches both the legacy and the branch-partitioned
  -- session layouts; the slug is the first path component of the filename. The
  -- raw-line read (delim = E'\x01' for one physical line per row, quoting
  -- disabled) tolerates malformed lines that would abort a read_json_auto scan.
  audit_events AS (
    SELECT
      TRY(json_extract_string(j, '$.task_id')) AS task_id,
      TRY(json_extract_string(j, '$.shape'))   AS shape
    FROM read_csv(
      '*/**/audit.jsonl',
      columns = {'j': 'VARCHAR'},
      delim = E'\x01',
      quote = '', escape = '',
      header = false,
      auto_detect = false,
      ignore_errors = true,
      filename = true
    )
    WHERE json_valid(j)
  ),

  -- The shape a task was classified as (planner-emitted fact).
  task_shape AS (
    SELECT DISTINCT task_id, shape
    FROM audit_events
    WHERE task_id IS NOT NULL AND shape IS NOT NULL
  ),

  -- Per-slug calibration: the slug is the first path component of the
  -- calibration filename, so segment is known without any session join.
  -- QUALIFY deduplicates to the latest record per (session_id, taskId) so that
  -- re-verify rewrites do not inflate counts — mirrors self_fail_vs_verdict_gap's
  -- existing pattern exactly.
  verdicts AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1) AS slug,
      TRY(json_extract_string(j, '$.taskId'))       AS task_id,
      TRY(json_extract_string(j, '$.verdict'))      AS verdict
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
    QUALIFY row_number() OVER (
      PARTITION BY TRY(json_extract_string(j, '$.session_id')),
                   TRY(json_extract_string(j, '$.taskId'))
      ORDER BY TRY(json_extract_string(j, '$.timestamp')) DESC
    ) = 1
  ),

  classified AS (
    SELECT
      CASE WHEN v.slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment,
      t.shape,
      v.verdict
    FROM verdicts v
    JOIN task_shape t ON v.task_id = t.task_id
  )

SELECT
  segment,
  shape,
  count(*)                                              AS task_count,
  count(*) FILTER (WHERE verdict = 'FAIL')              AS fail_count,
  round(count(*) FILTER (WHERE verdict = 'FAIL') * 1.0 / count(*), 4) AS fail_rate
FROM classified
GROUP BY ALL;
