-- Shape distribution: per-shape counts of emitted (session, assertion) facts,
-- split by segment (dogfood vs feature).
--
-- Reads session audit.jsonl IN PLACE. The shape dimension is emitted going
-- forward by the planner; historical records lack it and are excluded here
-- (a NULL shape is not a category to count).
--
-- Audit lines are read as RAW physical lines (one VARCHAR per line), filtered
-- with json_valid, and projected with TRY(json_extract_string(...)). This
-- tolerates malformed/truncated legacy audit files: read_json_auto aborts the
-- entire scan on the first bad line in any matched file (ignore_errors does not
-- help with truncated newline_delimited JSON), whereas the raw-line read skips
-- only the bad lines. The TRY wrapper is load-bearing: json_extract_string
-- THROWS on a malformed fragment (e.g. a bare "{" line split out of an older
-- pretty-printed multi-line record), and the optimizer may evaluate the
-- projection on rows the json_valid filter would discard — TRY makes such a
-- call return NULL instead of aborting the query. json_extract_string also
-- returns NULL for an absent key, exactly reproducing the previous
-- union_by_name NULL-fill across the two audit line-shapes ({ts,tool,file} and
-- {event,task_id,...}).
--
-- Run from the .rnd root (the directory whose children are slug dirs):
--   duckdb -c ".read lib/stats/shape_distribution.sql" -c "SELECT * FROM shape_distribution ORDER BY segment, shape"

CREATE OR REPLACE VIEW shape_distribution AS
WITH
  -- Dogfood allowlist: a source slug in this list is the rnd-framework repo
  -- instrumenting itself; everything else is a downstream feature project.
  dogfood_slugs AS (
    SELECT unnest(['claude-130cb64f']) AS slug
  ),

  -- Every audit JSONL line across all slugs and BOTH on-disk session layouts.
  -- The single recursive glob '*/**/audit.jsonl' matches the legacy layout
  -- (<slug>/sessions/<id>/audit.jsonl) and the current branch-partitioned
  -- layout (<slug>/branches/<branch>/sessions/<id>/audit.jsonl), including
  -- branch names that contain slashes. The slug is the FIRST path component of
  -- the filename (relative to cwd). The raw-line read (delim = E'\x01', a byte
  -- never present in JSONL, gives one physical line per row; quoting disabled so
  -- JSON's escaped quotes do not mangle lines) tolerates malformed lines that
  -- would abort a read_json_auto scan; json_valid drops them, json_extract_string
  -- NULL-fills absent keys across the two audit line-shapes.
  audit_events AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1) AS slug,
      TRY(json_extract_string(j, '$.shape'))        AS shape
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

  shape_facts AS (
    SELECT
      slug,
      shape,
      CASE WHEN slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment
    FROM audit_events
    WHERE shape IS NOT NULL
  )

SELECT
  segment,
  shape,
  count(*) AS task_count
FROM shape_facts
GROUP BY ALL;
