-- Builder self-fail vs verifier-verdict gap: per segment, how often the
-- builder's own self-assessment disagreed with the verifier on whether the
-- task failed. A gap in either direction is a calibration signal — builders
-- who pass work the verifier fails (over-confident) or fail work the verifier
-- passes (under-confident).
--
-- The two sides use DIFFERENT failure vocabularies and must not be unified:
--   * Builder build_status is a raw 4-valued code: DONE | DONE_WITH_CONCERNS |
--     NEEDS_CONTEXT | BLOCKED (emitted by self-assessment-producer.sh). The
--     pass/fail collapse lives HERE, not in the producer: a builder "fail" is a
--     status of NEEDS_CONTEXT or BLOCKED (the builder could not complete the
--     task). DONE_WITH_CONCERNS is NOT a failure — criteria are met and concerns
--     are advisory; folding it into FAIL (as the pre-build_status producer did
--     by inferring FAIL from full-template *shape*) inflated this gap with false
--     builder self-FAILs.
--   * Legacy fallback: records emitted before the build_status migration carry a
--     binary `self_verdict` (PASS|FAIL) instead. Such a record self-fails iff
--     `self_verdict = 'FAIL'`. self_fail COALESCEs build_status first, then the
--     legacy field, so old and new corpora both read correctly.
--   * Verifier verdict is PASS | NEEDS_ITERATION | PASS_QUALITY_NEEDS_ITERATION
--     (the literal FAIL string is retired). A verifier "fail" is therefore any
--     non-PASS verdict — `verdict <> 'PASS'` — NOT `verdict = 'FAIL'`, which
--     reads zero on all modern data.
--
-- Builder self-verdict comes from the builder_self_assessment audit event;
-- verifier verdict comes from per-slug calibration.jsonl. The segment is the
-- first path component of the calibration filename (no join needed for segment),
-- but the builder↔verifier pairing IS keyed on (session_id, task_id): both
-- payloads carry session_id, and a bare-task_id join would merge unrelated tasks
-- that share an ID across sessions (e.g. a re-plan reusing M1.T01.<slug>). A
-- (session, task) pair contributes one row only when both signals exist. Both
-- signals are deduped to the LATEST record per (session, task) — an iterated task
-- emits multiple of each within a session — so the gap is a clean
-- per-(session,task) count, never per-attempt and never cross-session-merged.
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
--   duckdb -c ".read lib/stats/self_fail_vs_verdict_gap.sql" -c "SELECT * FROM self_fail_vs_verdict_gap ORDER BY segment"

CREATE OR REPLACE VIEW self_fail_vs_verdict_gap AS
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

  audit_events AS (
    SELECT
      TRY(json_extract_string(j, '$.session_id'))   AS session_id,
      TRY(json_extract_string(j, '$.task_id'))      AS task_id,
      TRY(json_extract_string(j, '$.event'))        AS event,
      TRY(json_extract_string(j, '$.build_status')) AS build_status,
      TRY(json_extract_string(j, '$.self_verdict')) AS self_verdict,
      TRY(json_extract_string(j, '$.timestamp'))    AS ts
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

  -- Builder's own status per task — latest attempt only. Carries both the new
  -- build_status and the legacy self_verdict; the collapse happens in `paired`.
  self_assessment AS (
    SELECT session_id, task_id, build_status, self_verdict
    FROM audit_events
    WHERE event = 'builder_self_assessment' AND task_id IS NOT NULL
    QUALIFY row_number() OVER (PARTITION BY session_id, task_id ORDER BY ts DESC) = 1
  ),

  -- Per-slug calibration: slug is the first path component of the filename.
  verdicts AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1) AS slug,
      TRY(json_extract_string(j, '$.session_id'))   AS session_id,
      COALESCE(TRY(json_extract_string(j, '$.task_id')), TRY(json_extract_string(j, '$.taskId'))) AS task_id,
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
                   COALESCE(TRY(json_extract_string(j, '$.task_id')), TRY(json_extract_string(j, '$.taskId')))
      ORDER BY TRY(json_extract_string(j, '$.timestamp')) DESC
    ) = 1
  ),

  paired AS (
    SELECT
      CASE WHEN v.slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment,
      COALESCE(
        a.build_status IN ('NEEDS_CONTEXT', 'BLOCKED'),  -- new records
        a.self_verdict = 'FAIL'                          -- legacy fallback
      )                                      AS self_fail,
      (v.verdict <> 'PASS')                  AS verifier_fail
    FROM verdicts v
    JOIN self_assessment a
      ON v.session_id = a.session_id AND v.task_id = a.task_id
  )

SELECT
  segment,
  count(*)                                                    AS task_count,
  count(*) FILTER (WHERE self_fail)                           AS self_fail_count,
  count(*) FILTER (WHERE verifier_fail)                       AS verifier_fail_count,
  count(*) FILTER (WHERE self_fail <> verifier_fail)          AS gap_count
FROM paired
GROUP BY ALL;
