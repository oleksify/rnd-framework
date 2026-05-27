-- Builder self-fail vs verifier-verdict gap: per segment, how often the
-- builder's own self-assessment disagreed with the verifier on whether the
-- task failed. A gap in either direction is a calibration signal — builders
-- who pass work the verifier fails (over-confident) or fail work the verifier
-- passes (under-confident).
--
-- Builder self-verdict comes from the builder_self_assessment audit event;
-- verifier verdict comes from per-slug calibration.jsonl, whose slug (and thus
-- segment) is the first path component of the calibration filename — no session
-- join is needed. A task contributes one row only when both signals exist.
-- Both signals are deduped to the LATEST record per task (an iterated task emits
-- multiple of each) so the gap is a clean per-task count, never per-attempt.
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
  -- Dogfood allowlist: a source slug in this list is the rnd-framework repo
  -- instrumenting itself; everything else is a downstream feature project.
  dogfood_slugs AS (
    SELECT unnest(['claude-130cb64f']) AS slug
  ),

  audit_events AS (
    SELECT
      TRY(json_extract_string(j, '$.task_id'))      AS task_id,
      TRY(json_extract_string(j, '$.event'))        AS event,
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

  -- Builder's own pass/fail call per task — latest attempt only.
  self_assessment AS (
    SELECT task_id, self_verdict
    FROM audit_events
    WHERE event = 'builder_self_assessment' AND task_id IS NOT NULL
    QUALIFY row_number() OVER (PARTITION BY task_id ORDER BY ts DESC) = 1
  ),

  -- Per-slug calibration: slug is the first path component of the filename.
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
      PARTITION BY TRY(json_extract_string(j, '$.taskId'))
      ORDER BY TRY(json_extract_string(j, '$.timestamp')) DESC
    ) = 1
  ),

  paired AS (
    SELECT
      CASE WHEN v.slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment,
      (a.self_verdict = 'FAIL')              AS self_fail,
      (v.verdict = 'FAIL')                   AS verifier_fail
    FROM verdicts v
    JOIN self_assessment a ON v.task_id = a.task_id
  )

SELECT
  segment,
  count(*)                                                    AS task_count,
  count(*) FILTER (WHERE self_fail)                           AS self_fail_count,
  count(*) FILTER (WHERE verifier_fail)                       AS verifier_fail_count,
  count(*) FILTER (WHERE self_fail <> verifier_fail)          AS gap_count
FROM paired
GROUP BY ALL;
