-- Scope-coverage gate event counts: how often the scope_coverage_gate fired,
-- split by violation kind (scope_creep vs scope_miss) and segment (dogfood vs
-- feature). Each gate_fired row carries assertion_id = 'scope_creep' or
-- 'scope_miss' — that field is repurposed here as a kind discriminator.
--
-- Events come from audit.jsonl files, read as RAW physical lines (one VARCHAR
-- per line, delim = E'\x01', quoting disabled) to tolerate malformed/truncated
-- legacy files. TRY(json_extract_string(...)) is load-bearing: the DuckDB
-- optimizer may push projections past the json_valid filter, so TRY returns
-- NULL instead of aborting on a malformed fragment.
--
-- Segment is derived from the audit filename's first path component (the slug),
-- matched against the RND_DOGFOOD_SLUGS env var — the single source of truth;
-- no hardcoded slug in this file.
--
-- Run from the .rnd root:
--   duckdb -c ".read lib/stats/scope_coverage.sql" -c "SELECT * FROM scope_coverage ORDER BY segment, kind"

CREATE OR REPLACE VIEW scope_coverage AS
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
  gate_events AS (
    SELECT
      regexp_extract(filename, '^\.?/?([^/]+)/', 1)               AS slug,
      TRY(json_extract_string(j, '$.assertion_id'))                AS kind
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
      AND TRY(json_extract_string(j, '$.event'))  = 'gate_fired'
      AND TRY(json_extract_string(j, '$.tool'))   = 'scope_coverage_gate'
      AND TRY(json_extract_string(j, '$.assertion_id')) IS NOT NULL
  ),

  classified AS (
    SELECT
      CASE WHEN g.slug IN (SELECT slug FROM dogfood_slugs)
           THEN 'dogfood' ELSE 'feature' END AS segment,
      g.kind
    FROM gate_events g
  )

SELECT
  segment,
  kind,
  count(*) AS event_count
FROM classified
GROUP BY ALL;
