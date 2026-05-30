-- Drift watch: per-session iteration load and replan frequency, with rolling
-- linear regression slopes to surface whether pipeline quality is drifting.
--
-- Reads two substrates:
--
--   (1) Per-slug calibration.jsonl for the per-session iteration metric.
--       One calibration record per verifier run; iteration depth per task is
--       derived as COALESCE(stored iterationCount, count-to-first-PASS,
--       total records) matching the iteration_depth.sql derivation. The
--       per-session metric is the SUM of per-task iteration depth across the
--       session. session_id is read with COALESCE($.session_id, $.sessionId)
--       to tolerate both producer spellings.
--
--   (2) Session audit.jsonl across all slug dirs for replan_started events.
--       replan_started records carry NO session_id JSON key — the session
--       identity is extracted from the file path via the regex
--       regexp_extract(filename, 'sessions/([^/]+)/audit\.jsonl', 1).
--       This is load-bearing: using a JSON key would silently drop all
--       replan events and report 0 replans everywhere.
--
--   Sessions absent from the replan substrate (no replan_started events) get
--   replan_count = 0, never NULL. COALESCE(replan_agg.replan_count, 0) is the
--   mechanism; without it the LEFT JOIN would produce NULLs for clean sessions.
--
-- Slope columns (iter_slope, replan_slope) are computed via regr_slope over a
-- 10-row rolling window (9 PRECEDING AND CURRENT ROW). A window narrower than
-- 2 rows produces float nan — no string sentinel is emitted. window_n reports
-- the actual frame width (≥1, ≤10) so callers can threshold on evidence count.
--
-- session_ordinal is a strictly-increasing 1..N integer within each segment,
-- ordered by (session_ts, session_id). It serves as the x-axis for regr_slope.
-- Ties on session_ts are broken by session_id (string sort), ensuring
-- deterministic ordinals even when timestamps are missing or colliding.
--
-- Run from the .rnd root (directory whose children are slug dirs):
--   export RND_DOGFOOD_SLUGS="my-slug-hash"
--   duckdb -c ".read lib/stats/drift_watch.sql" -c "SELECT * FROM drift_watch ORDER BY segment, session_ordinal"

CREATE OR REPLACE VIEW drift_watch AS
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

  -- Substrate 1: calibration records — derive per-task iteration depth using
  -- the same derivation as iteration_depth.sql (COALESCE of stored field,
  -- first-PASS row-number, total record count). session_id tolerates both
  -- producer spellings (snake_case and camelCase).
  cal_records AS (
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

  cal_ranked AS (
    SELECT
      slug, session_id, task_id, verdict, ts, stored_iter,
      ROW_NUMBER() OVER (
        PARTITION BY slug, session_id, task_id
        ORDER BY ts NULLS LAST
      ) AS rn
    FROM cal_records
  ),

  cal_per_task AS (
    SELECT
      slug,
      session_id,
      task_id,
      MAX(stored_iter)                             AS stored_iter,
      MIN(CASE WHEN verdict = 'PASS' THEN rn END)  AS first_pass_rn,
      count(*)                                     AS total_records,
      MAX(ts)                                      AS task_ts
    FROM cal_ranked
    GROUP BY 1, 2, 3
  ),

  -- Sum per-task iteration depth into a single per-session figure.
  -- session_ts is the MAX verdict timestamp across tasks in the session.
  cal_per_session AS (
    SELECT
      slug,
      session_id,
      SUM(COALESCE(stored_iter, first_pass_rn, total_records)) AS iter_metric,
      MAX(task_ts)                                              AS session_ts
    FROM cal_per_task
    GROUP BY 1, 2
  ),

  -- Substrate 2: audit.jsonl across all slug+session dirs — replan_started events.
  -- session_id comes from the file path, NOT from a JSON key (replan_started
  -- records do not carry a session_id field).
  replan_events AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1)                           AS slug,
      regexp_extract(filename, 'sessions/([^/]+)/audit\.jsonl', 1)            AS session_id,
      TRY(json_extract_string(j, '$.timestamp'))                              AS ts
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
      AND TRY(json_extract_string(j, '$.event')) = 'replan_started'
  ),

  replan_per_session AS (
    SELECT
      slug,
      session_id,
      count(*)   AS replan_count,
      MAX(ts)    AS replan_ts
    FROM replan_events
    WHERE session_id != ''
    GROUP BY 1, 2
  ),

  -- Session spine: full set of (slug, session_id) appearing in EITHER substrate.
  -- session_ts is COALESCE of the calibration and replan timestamps so that
  -- sessions appearing only in the replan substrate still get a usable timestamp.
  spine AS (
    SELECT
      c.slug,
      c.session_id,
      COALESCE(c.session_ts, r.replan_ts) AS session_ts
    FROM cal_per_session c
    LEFT JOIN replan_per_session r USING (slug, session_id)

    UNION

    SELECT
      r.slug,
      r.session_id,
      r.replan_ts AS session_ts
    FROM replan_per_session r
    LEFT JOIN cal_per_session c USING (slug, session_id)
    WHERE c.slug IS NULL
  ),

  -- Attach segment and ordinal.
  spine_classified AS (
    SELECT
      CASE WHEN s.slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment,
      s.slug,
      s.session_id,
      s.session_ts,
      ROW_NUMBER() OVER (
        PARTITION BY
          CASE WHEN s.slug IN (SELECT slug FROM dogfood_slugs)
               THEN 'dogfood' ELSE 'feature' END
        ORDER BY s.session_ts NULLS LAST, s.session_id
      )                                      AS session_ordinal
    FROM spine s
  ),

  -- Join metrics onto the spine.
  joined AS (
    SELECT
      sc.segment,
      sc.session_ordinal,
      sc.session_id,
      sc.session_ts,
      COALESCE(c.iter_metric, 0)     AS iter_metric,
      COALESCE(r.replan_count, 0)    AS replan_count
    FROM spine_classified sc
    LEFT JOIN cal_per_session   c USING (slug, session_id)
    LEFT JOIN replan_per_session r USING (slug, session_id)
  )

SELECT
  segment,
  session_ordinal,
  session_id,
  CAST(iter_metric AS DOUBLE)                                  AS iter_metric,
  replan_count,
  regr_slope(CAST(iter_metric AS DOUBLE), CAST(session_ordinal AS DOUBLE)) OVER (
    PARTITION BY segment
    ORDER BY session_ordinal
    ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
  )                                                            AS iter_slope,
  regr_slope(CAST(replan_count AS DOUBLE), CAST(session_ordinal AS DOUBLE)) OVER (
    PARTITION BY segment
    ORDER BY session_ordinal
    ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
  )                                                            AS replan_slope,
  count(*) OVER (
    PARTITION BY segment
    ORDER BY session_ordinal
    ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
  )                                                            AS window_n
FROM joined
ORDER BY segment, session_ordinal;
