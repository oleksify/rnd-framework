-- Historical backfill: derive verdict, segment, and outcome for every
-- calibration verdict record. Records that predate the shape/confidence emit
-- have those dimensions as NULL — this view makes the gap explicit rather
-- than dropping historical rows.
--
-- Segment is derived DIRECTLY from the per-slug calibration filename's slug
-- (first path component) — no session join is needed.
--
-- Per-assertion outcome is a computed expression (never written back):
--   first-try-pass  — passed on the first build-verify cycle
--   iter-pass       — passed after one or more iterations
--   replanned-around — verifier returned NEEDS_ITERATION or
--                      PASS_QUALITY_NEEDS_ITERATION (still open)
--   abandoned       — verifier returned FAIL (no further iteration)
--
-- Correction records (carry a `correction` field, no `verdict`) are excluded.
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
--   duckdb -c ".read lib/stats/backfill.sql" -c "SELECT * FROM backfill ORDER BY segment, task_id"

CREATE OR REPLACE VIEW backfill AS
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

  -- Per-slug calibration: slug is the first path component of the filename.
  calibration AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1)                    AS slug,
      COALESCE(TRY(json_extract_string(j, '$.task_id')), TRY(json_extract_string(j, '$.taskId'))) AS task_id,
      COALESCE(TRY(json_extract_string(j, '$.session_id')), TRY(json_extract_string(j, '$.sessionId'))) AS session_id,
      TRY(json_extract_string(j, '$.verdict'))                         AS verdict,
      CAST(TRY(json_extract_string(j, '$.iterationCount')) AS INTEGER) AS iteration_count,
      TRY(json_extract_string(j, '$.criticality'))                     AS criticality
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
  )

SELECT
  c.task_id,
  c.session_id,
  c.verdict,
  c.iteration_count,
  c.criticality,
  CASE WHEN c.slug IN (SELECT slug FROM dogfood_slugs)
       THEN 'dogfood' ELSE 'feature' END                AS segment,

  -- shape and confidence are planner-emitted audit facts; calibration records
  -- never carry them — project NULL so consumers can distinguish "not emitted"
  -- from "unknown".
  NULL::VARCHAR                                          AS shape,
  NULL::VARCHAR                                          AS confidence,

  -- Derived outcome: a computed expression from verdict + iteration_count.
  -- Not written back anywhere — query this view to get the value.
  CASE
    WHEN c.verdict = 'PASS'
         AND c.iteration_count = 0                       THEN 'first-try-pass'
    WHEN c.verdict = 'PASS'
         AND c.iteration_count > 0                       THEN 'iter-pass'
    WHEN c.verdict IN (
           'NEEDS_ITERATION',
           'PASS_QUALITY_NEEDS_ITERATION'
         )                                               THEN 'replanned-around'
    WHEN c.verdict = 'FAIL'                              THEN 'abandoned'
  END                                                    AS outcome

FROM calibration c;
