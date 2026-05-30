-- Per-category post-pipeline-review findings: for each (segment, category),
-- how many finding rows (review_found = true) were recorded.
--
-- A finding row whose `category` is NULL or absent (legacy rows predating the
-- category field) is bucketed as the literal string 'uncategorized' rather than
-- dropped or erroring — COALESCE is the mechanism (see raw_findings CTE below).
--
-- post-review.jsonl lives at the slug root (sibling to calibration.jsonl):
--   <slug>/post-review.jsonl
-- The glob is tight: */post-review.jsonl (never *-review.jsonl).
--
-- Fields consumed per row:
--   review_found  BOOL    — only rows where review_found = true are counted
--   session_id    STRING  — YYYYMMDD-HHMMSS-xxxx sortable session ID
--   category      STRING? — one of the x-review-category-vocab slugs, or absent
--
-- Run from the .rnd root (the directory whose children are slug dirs):
--   duckdb -c ".read lib/stats/post_review_categories.sql" \
--          -c "SELECT * FROM post_review_categories ORDER BY segment, category"

CREATE OR REPLACE VIEW post_review_categories AS
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
  -- COALESCE maps a NULL/absent category to the literal 'uncategorized' so
  -- legacy rows are bucketed rather than dropped.
  raw_findings AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1)                              AS slug,
      TRY(json_extract_string(j, '$.session_id'))                                AS session_id,
      TRY(CAST(json_extract(j, '$.review_found') AS BOOLEAN))                    AS review_found,
      COALESCE(TRY(json_extract_string(j, '$.category')), 'uncategorized')       AS category
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
  ),

  classified AS (
    SELECT
      CASE WHEN slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment,
      category,
      review_found
    FROM raw_findings
  )

SELECT
  segment,
  category,
  count(*) FILTER (WHERE review_found = true) AS finding_count
FROM classified
GROUP BY ALL;
