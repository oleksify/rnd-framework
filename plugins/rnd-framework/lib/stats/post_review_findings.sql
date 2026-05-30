-- Per-shape post-pipeline-review findings: for each (segment, shape), how many
-- review sessions ran, how many had at least one real finding, and how many
-- sessions where the verifier said PASS but the post-review found an issue
-- (the verifier-said-PASS-vs-review-found gap).
--
-- Input grain: post-review.jsonl is PER-FINDING — one row per finding per
-- session. A session that surfaces two findings contributes two rows.
-- The view aggregates to per-(session, shape) FIRST (a single CTE) so that
-- count(*) over the aggregate never exceeds the distinct (session, shape)
-- count. FM2: a 2-finding session is ONE dirty session, not two.
--
-- post-review.jsonl lives at the slug root (sibling to calibration.jsonl):
--   <slug>/post-review.jsonl
-- The glob is tight: */post-review.jsonl (never *-review.jsonl).
--
-- Fields consumed per row:
--   shape             STRING  — shape attributed to the finding
--   severity          STRING  — critical|major|minor|info (not aggregated here)
--   verifier_said_PASS BOOL   — was the verifier verdict PASS for this task?
--   review_found      BOOL    — did the post-review actually find an issue?
--   session_id        STRING  — YYYYMMDD-HHMMSS-xxxx sortable session ID
--   timestamp         STRING  — ISO 8601 timestamp
--
-- Run from the .rnd root (the directory whose children are slug dirs):
--   duckdb -c ".read lib/stats/post_review_findings.sql" \
--          -c "SELECT * FROM post_review_findings ORDER BY segment, shape"

CREATE OR REPLACE VIEW post_review_findings AS
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

  -- Raw per-finding rows from every slug's post-review.jsonl. The raw-line
  -- read (delim = E'\x01' for one physical line per row, quoting disabled)
  -- tolerates malformed lines that would abort a read_json_auto scan.
  -- TRY is load-bearing: json_extract_string THROWS on malformed fragments
  -- and the optimizer may run the projection on rows json_valid would discard.
  raw_findings AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1)            AS slug,
      TRY(json_extract_string(j, '$.shape'))                   AS shape,
      TRY(json_extract_string(j, '$.session_id'))              AS session_id,
      TRY(CAST(json_extract(j, '$.verifier_said_PASS') AS BOOLEAN)) AS verifier_said_pass,
      TRY(CAST(json_extract(j, '$.review_found') AS BOOLEAN))      AS review_found
    FROM read_csv(
      '*/post-review.jsonl',
      columns = {'j': 'VARCHAR'},
      delim = E'\x01',
      quote = '', escape = '',
      header = false,
      auto_detect = false,
      ignore_errors = true,
      filename = true
    )
    WHERE json_valid(j)
      AND TRY(json_extract_string(j, '$.session_id')) IS NOT NULL
      AND TRY(json_extract_string(j, '$.shape'))      IS NOT NULL
  ),

  -- Aggregate per-finding rows to per-(session, shape) BEFORE counting.
  -- This is the grain-reduction step: a session with N findings on the same
  -- shape is collapsed to one row. A session is "dirty" iff at least one
  -- finding row has review_found=true; "pass_but_found" iff at least one row
  -- has verifier_said_PASS=true AND review_found=true.
  per_session_shape AS (
    SELECT
      slug,
      session_id,
      shape,
      bool_or(review_found = true)                                          AS has_finding,
      bool_or(verifier_said_pass = true AND review_found = true)            AS pass_but_found
    FROM raw_findings
    GROUP BY slug, session_id, shape
  ),

  classified AS (
    SELECT
      CASE WHEN slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment,
      shape,
      has_finding,
      pass_but_found
    FROM per_session_shape
  )

SELECT
  segment,
  shape,
  count(*)                                        AS review_count,
  count(*) FILTER (WHERE has_finding)             AS finding_count,
  count(*) FILTER (WHERE pass_but_found)          AS gap_count
FROM classified
GROUP BY ALL;
