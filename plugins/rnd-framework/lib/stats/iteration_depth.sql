-- Iteration-depth distribution: histogram of how many build-verify cycles
-- tasks needed, split by segment.
--
-- Two calibration-record shapes are tolerated:
--
--   Mode A (legacy/fixture): one calibration record per task, carrying the
--     final iterationCount as a stored field. The stored value is read
--     directly.
--
--   Mode B (current production producer): one calibration record per verifier
--     run; the producer does not write iterationCount. Iteration depth is
--     derived as the count of records up to and INCLUDING the first PASS in
--     chronological order (by timestamp). Records after the first PASS are
--     re-verifies of an already-passing task, NOT new build-verify cycles,
--     and are excluded. Tasks that never reach PASS contribute their total
--     record count.
--
-- COALESCE(stored_iter, derived_iter) prefers the stored field when present,
-- so fixture validation is unchanged.
--
-- session_id is read with COALESCE on both spellings: $.session_id (current
-- producer, snake_case) and $.sessionId (fixture/legacy, camelCase). Without
-- this fallback the per-task partition would degenerate to one bucket per slug
-- and re-verifies of different sessions would be conflated.
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

  records AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1)                    AS slug,
      COALESCE(
        TRY(json_extract_string(j, '$.session_id')),
        TRY(json_extract_string(j, '$.sessionId')),
        ''
      )                                                                AS session_id,
      COALESCE(TRY(json_extract_string(j, '$.task_id')), TRY(json_extract_string(j, '$.taskId'))) AS task_id,
      TRY(json_extract_string(j, '$.verdict'))                         AS verdict,
      TRY(json_extract_string(j, '$.timestamp'))                       AS ts,
      CAST(TRY(json_extract_string(j, '$.iterationCount')) AS INTEGER) AS stored_iter
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
      AND TRY(json_extract_string(j, '$.verdict')) IS NOT NULL
      AND COALESCE(TRY(json_extract_string(j, '$.task_id')), TRY(json_extract_string(j, '$.taskId'))) IS NOT NULL
  ),

  ranked AS (
    SELECT
      slug, session_id, task_id, verdict, ts, stored_iter,
      ROW_NUMBER() OVER (
        PARTITION BY slug, session_id, task_id
        ORDER BY ts NULLS LAST
      ) AS rn
    FROM records
  ),

  per_task AS (
    SELECT
      slug,
      session_id,
      task_id,
      MAX(stored_iter)                                                AS stored_iter,
      MIN(CASE WHEN verdict = 'PASS' THEN rn END)                     AS first_pass_rn,
      count(*)                                                        AS total_records
    FROM ranked
    GROUP BY 1, 2, 3
  ),

  classified AS (
    SELECT
      CASE WHEN slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END                          AS segment,
      COALESCE(stored_iter, first_pass_rn, total_records)             AS iteration_count
    FROM per_task
  )

SELECT
  segment,
  iteration_count,
  count(*) AS task_count
FROM classified
GROUP BY ALL;
