-- Iteration reasons: distribution of non-PASS verdicts in calibration, by
-- segment. Each non-PASS verdict is a reason the build-verify cycle did not
-- terminate cleanly at that record:
--
--   NEEDS_ITERATION                  — assertions failed; rebuild required
--   PASS_QUALITY_NEEDS_ITERATION     — quality issues short of failure
--   FAIL                             — legacy verdict (Gate 3 now collapses
--                                      FAIL into NEEDS_ITERATION at the
--                                      task-aggregate level, so this only
--                                      appears in historical or fixture data)
--
-- The view surfaces every non-PASS record, so a task that iterated twice
-- contributes two rows. This stays correct under both calibration-record
-- shapes:
--
--   Mode A (legacy/fixture): one record per task; a non-PASS verdict here is
--     the final outcome and is itself a reason iteration was needed.
--   Mode B (current production): one record per verifier run; non-PASS
--     records are exactly the cycle-triggering events.
--
-- Sibling view: iteration_depth (which COUNTS cycles per task). This view
-- describes WHY they iterated.
--
-- Run from the .rnd root:
--   duckdb -c ".read lib/stats/iteration_reasons.sql" -c "SELECT * FROM iteration_reasons ORDER BY segment, reason_verdict"

CREATE OR REPLACE VIEW iteration_reasons AS
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
      regexp_extract(filename, '^\.?/?([^/]+)/', 1) AS slug,
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
      AND TRY(json_extract_string(j, '$.verdict')) IS NOT NULL
  )

SELECT
  CASE WHEN slug IN (SELECT slug FROM dogfood_slugs)
       THEN 'dogfood' ELSE 'feature' END AS segment,
  verdict                                AS reason_verdict,
  count(*)                               AS occurrences
FROM records
WHERE verdict <> 'PASS'
GROUP BY ALL;
