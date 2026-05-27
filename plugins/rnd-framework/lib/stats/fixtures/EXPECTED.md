# Expected Aggregates — Stats View Fixture

This file documents the hand-computed expected output of every view in
`lib/stats/*.sql` when run against the committed fixture tree in this
directory. The fixture is deterministic — re-running any view from this
directory must reproduce the tables below exactly.

This fixture directory is the `.rnd`-root analog: its immediate children are
per-project slug dirs, each holding its own `calibration.jsonl` and sessions
under both the legacy and the branch-partitioned layouts. This mirrors the real
`~/.claude/.rnd/` tree so the views are validated against the layout they will
actually meet in production.

## How to run

From this fixture directory (`lib/stats/fixtures/`):

```sh
duckdb -c ".read ../shape_distribution.sql"        -c "SELECT * FROM shape_distribution ORDER BY segment, shape"
duckdb -c ".read ../per_shape_fail_rate.sql"       -c "SELECT * FROM per_shape_fail_rate ORDER BY segment, shape"
duckdb -c ".read ../iteration_depth.sql"           -c "SELECT * FROM iteration_depth ORDER BY segment, iteration_count"
duckdb -c ".read ../self_fail_vs_verdict_gap.sql"  -c "SELECT * FROM self_fail_vs_verdict_gap ORDER BY segment"
duckdb -c ".read ../fail_rate_over_time.sql"       -c "SELECT * FROM fail_rate_over_time ORDER BY segment, week"
duckdb -c ".read ../backfill.sql"                  -c "SELECT * FROM backfill ORDER BY segment, task_id"
```

The audit views glob `*/**/audit.jsonl` (a single recursive glob that matches
both the legacy `<slug>/sessions/<id>/audit.jsonl` and the branch-partitioned
`<slug>/branches/<branch>/sessions/<id>/audit.jsonl` layouts, including branch
names with slashes). The calibration views glob `*/calibration.jsonl`. In every
view the slug is the FIRST path component of the matched filename
(`regexp_extract(filename, '^\.?/?([^/]+)/', 1)`), which is the slug for both
layouts and for both audit and calibration files.

## Fixture shape

Two source slugs exercise the segment dimension, each laid out like a real
`.rnd/<slug>/` tree (its own `calibration.jsonl`, plus sessions under both
on-disk layouts):

- `claude-130cb64f` — the dogfood slug (in the inline allowlist) → segment `dogfood`
  - `claude-130cb64f/calibration.jsonl` — its verdicts (incl. the correction record)
  - `claude-130cb64f/sessions/s-df-1/audit.jsonl` — legacy layout
  - `claude-130cb64f/branches/main/sessions/s-df-2/audit.jsonl` — branch-partitioned layout
  - `claude-130cb64f/sessions/s-df-hist/audit.jsonl` — legacy layout (historical)
- `acme-widgets-7f3a1b2c` — a downstream feature project (not in the allowlist) → segment `feature`
  - `acme-widgets-7f3a1b2c/calibration.jsonl` — its verdicts
  - `acme-widgets-7f3a1b2c/branches/release/v2/sessions/s-ft-1/audit.jsonl` — branch-partitioned layout with a SLASH in the branch name (`release/v2`), proving the recursive glob and first-component slug extraction handle nested branch dirs
  - `acme-widgets-7f3a1b2c/sessions/s-ft-hist/audit.jsonl` — legacy layout (historical)

There is NO cross-slug root `calibration.jsonl` — calibration is per-slug, exactly
as in production. The segment of a verdict is read directly from its
`calibration.jsonl` file's slug (first path component); no session→slug join is
needed.

### Per-task fixture facts

Tasks with shape/confidence (planner-emitted; appear in audit events). The
`session` column shows which on-disk layout the task's session lives in:

| task_id          | slug                    | segment | session (layout)                              | shape            | builder self_verdict | verifier verdict | iterationCount | verdict timestamp     |
|------------------|-------------------------|---------|-----------------------------------------------|------------------|----------------------|------------------|----------------|-----------------------|
| M1.T-a.crud      | claude-130cb64f         | dogfood | s-df-1 (legacy)                               | crud             | PASS                 | PASS             | 0              | 2026-05-01T10:00:00Z  |
| M1.T-b.crud      | claude-130cb64f         | dogfood | s-df-1 (legacy)                               | crud             | PASS                 | FAIL             | 2              | 2026-05-01T10:10:00Z  |
| M1.T-c.docs      | claude-130cb64f         | dogfood | s-df-1 (legacy)                               | docs             | PASS                 | PASS             | 1              | 2026-05-01T10:20:00Z  |
| M1.T-d.schema    | claude-130cb64f         | dogfood | s-df-2 (branches/main)                        | schema-migration | FAIL                 | FAIL             | 3              | 2026-05-10T15:00:00Z  |
| M1.T-e.wiring    | claude-130cb64f         | dogfood | s-df-2 (branches/main)                        | wiring           | FAIL                 | PASS             | 1              | 2026-05-10T15:10:00Z  |
| M2.T-f.crud      | acme-widgets-7f3a1b2c   | feature | s-ft-1 (branches/release/v2 — slash branch)   | crud             | PASS                 | PASS             | 0              | 2026-05-05T09:00:00Z  |
| M2.T-g.docs      | acme-widgets-7f3a1b2c   | feature | s-ft-1 (branches/release/v2 — slash branch)   | docs             | PASS                 | PASS             | 1              | 2026-05-05T09:10:00Z  |

Historical tasks (no shape/confidence in audit; backfill view returns NULL for those columns):

| task_id       | slug                    | segment | session (layout)        | shape | builder self_verdict | verifier verdict | iterationCount | verdict timestamp     |
|---------------|-------------------------|---------|-------------------------|-------|----------------------|------------------|----------------|-----------------------|
| M0.T-h.setup  | claude-130cb64f         | dogfood | s-df-hist (legacy)      | —     | —                    | PASS             | 0              | 2026-03-15T08:30:00Z  |
| M0.T-i.setup  | acme-widgets-7f3a1b2c   | feature | s-ft-hist (legacy)      | —     | —                    | FAIL             | 2              | 2026-03-20T10:30:00Z  |

One **correction record** (`M1.T-b.crud`, `correction: FALSE_PASS`, no `verdict`
field) is present in `claude-130cb64f/calibration.jsonl` and MUST be excluded
from every verdict-rate aggregation below.

The audit files also contain ordinary Write/Edit lines (`{ts,tool,file}`,
no `event` key) and lifecycle lines (`SubagentStart`, `task_created`) to
exercise the `union_by_name=true` two-shape union; these carry no `shape`
and contribute to no aggregate.

---

## View 1 — `shape_distribution`

Per-shape count of emitted (session, assertion) facts, by segment.
Historical sessions carry no shape events — they contribute no rows here.

| segment | shape            | task_count |
|---------|------------------|------------|
| dogfood | crud             | 2          |
| dogfood | docs             | 1          |
| dogfood | schema-migration | 1          |
| dogfood | wiring           | 1          |
| feature | crud             | 1          |
| feature | docs             | 1          |

## View 2 — `per_shape_fail_rate`

Verifier-FAIL rate per (segment, shape). `fail_rate = fail_count / task_count`,
rounded to 4 decimals. Verdicts from `calibration.jsonl`; correction record excluded.
Historical tasks have no shape in audit — they are excluded from the join and do
not appear here.

| segment | shape            | task_count | fail_count | fail_rate |
|---------|------------------|------------|------------|-----------|
| dogfood | crud             | 2          | 1          | 0.5       |
| dogfood | docs             | 1          | 0          | 0.0       |
| dogfood | schema-migration | 1          | 1          | 1.0       |
| dogfood | wiring           | 1          | 0          | 0.0       |
| feature | crud             | 1          | 0          | 0.0       |
| feature | docs             | 1          | 0          | 0.0       |

## View 3 — `iteration_depth`

Histogram of `iterationCount` over verdict records, by segment.
Historical tasks contribute to the histogram: `M0.T-h.setup` (dogfood, count=0)
adds to dogfood/0; `M0.T-i.setup` (feature, count=2) adds a new feature/2 bucket.

| segment | iteration_count | task_count |
|---------|-----------------|------------|
| dogfood | 0               | 2          |
| dogfood | 1               | 2          |
| dogfood | 2               | 1          |
| dogfood | 3               | 1          |
| feature | 0               | 1          |
| feature | 1               | 1          |
| feature | 2               | 1          |

## View 4 — `self_fail_vs_verdict_gap`

Per segment: total paired tasks, count where the builder self-assessed FAIL,
count where the verifier returned FAIL, and the gap count (tasks where the two
disagree on FAIL-ness).

Historical sessions carry no builder_self_assessment events — they do not
contribute paired rows and so do not change these counts.

Dogfood disagreements: `M1.T-b.crud` (builder PASS, verifier FAIL) and
`M1.T-e.wiring` (builder FAIL, verifier PASS) → gap_count = 2.

Dedup regression lock: `M1.T-a.crud` carries TWO builder_self_assessment events
— an earlier `FAIL` (09:04:30) and a later `PASS` (09:05:00). The view keeps the
LATEST per task, so `M1.T-a.crud` counts once as PASS (no gap) and `task_count`
stays 5. Without the latest-per-task dedup it would count twice and inflate both
`task_count` (→6) and `gap_count` (→3); the counts below prove the dedup holds.

| segment | task_count | self_fail_count | verifier_fail_count | gap_count |
|---------|------------|-----------------|---------------------|-----------|
| dogfood | 5          | 2               | 2                   | 2         |
| feature | 2          | 0               | 0                   | 0         |

## View 5 — `fail_rate_over_time`

Verifier-FAIL rate bucketed by ISO week (`date_trunc('week', ...)`, Monday-start),
by segment. Historical tasks add two new week buckets:

- Week `2026-03-09` (Monday before 2026-03-15): dogfood `M0.T-h.setup` (PASS)
- Week `2026-03-16` (Monday before 2026-03-20): feature `M0.T-i.setup` (FAIL)
- Week `2026-04-27` contains the 2026-05-01 verdicts.
- Week `2026-05-04` contains the 2026-05-05 (feature) and 2026-05-10 (dogfood) verdicts.

| segment | week                | task_count | fail_count | fail_rate |
|---------|---------------------|------------|------------|-----------|
| dogfood | 2026-03-09 00:00:00 | 1          | 0          | 0.0       |
| dogfood | 2026-04-27 00:00:00 | 3          | 1          | 0.3333    |
| dogfood | 2026-05-04 00:00:00 | 2          | 1          | 0.5       |
| feature | 2026-03-16 00:00:00 | 1          | 1          | 1.0       |
| feature | 2026-05-04 00:00:00 | 2          | 0          | 0.0       |

---

## View 6 — `backfill`

SQL-only derivation of verdict, segment, outcome, and iteration count for every
calibration verdict record. `shape` and `confidence` are always `NULL` because
those dimensions are planner-emitted audit facts that do not exist in
`calibration.jsonl`. Correction records are excluded (no `verdict` field).

The `outcome` column is a CASE expression computed from `verdict` +
`iteration_count` — it is never written back.

Outcome logic:
- `verdict = 'PASS' AND iteration_count = 0` → `first-try-pass`
- `verdict = 'PASS' AND iteration_count > 0` → `iter-pass`
- `verdict IN ('NEEDS_ITERATION', 'PASS_QUALITY_NEEDS_ITERATION')` → `replanned-around`
- `verdict = 'FAIL'` → `abandoned`

Full expected output (`ORDER BY segment, task_id`):

| task_id       | session_id | verdict | iteration_count | criticality | segment | shape | confidence | outcome        |
|---------------|------------|---------|-----------------|-------------|---------|-------|------------|----------------|
| M0.T-h.setup  | s-df-hist  | PASS    | 0               | LOW         | dogfood | NULL  | NULL       | first-try-pass |
| M1.T-a.crud   | s-df-1     | PASS    | 0               | HIGH        | dogfood | NULL  | NULL       | first-try-pass |
| M1.T-b.crud   | s-df-1     | FAIL    | 2               | NORMAL      | dogfood | NULL  | NULL       | abandoned      |
| M1.T-c.docs   | s-df-1     | PASS    | 1               | LOW         | dogfood | NULL  | NULL       | iter-pass      |
| M1.T-d.schema | s-df-2     | FAIL    | 3               | HIGH        | dogfood | NULL  | NULL       | abandoned      |
| M1.T-e.wiring | s-df-2     | PASS    | 1               | NORMAL      | dogfood | NULL  | NULL       | iter-pass      |
| M0.T-i.setup  | s-ft-hist  | FAIL    | 2               | NORMAL      | feature | NULL  | NULL       | abandoned      |
| M2.T-f.crud   | s-ft-1     | PASS    | 0               | NORMAL      | feature | NULL  | NULL       | first-try-pass |
| M2.T-g.docs   | s-ft-1     | PASS    | 1               | LOW         | feature | NULL  | NULL       | iter-pass      |

Historical records are `M0.T-h.setup` (dogfood) and `M0.T-i.setup` (feature).
Both have `shape = NULL` and `confidence = NULL` because their sessions contain
no planner-emitted shape/confidence audit events.

---

## Segment filter (assertion `segment-filter-applies-dogfood-a`)

Filtering ANY view on `segment = 'dogfood'` returns only rows sourced from the
allowlisted slug (`claude-130cb64f`); `segment = 'feature'` returns only the
non-allowlisted (`acme-widgets-7f3a1b2c`) rows. Worked example on `shape_distribution`:

`WHERE segment = 'dogfood'` →

| segment | shape            | task_count |
|---------|------------------|------------|
| dogfood | crud             | 2          |
| dogfood | docs             | 1          |
| dogfood | schema-migration | 1          |
| dogfood | wiring           | 1          |

`WHERE segment = 'feature'` →

| segment | shape | task_count |
|---------|-------|------------|
| feature | crud  | 1          |
| feature | docs  | 1          |

---

## Real-tree layout (assertion `matches-real-tree-layout`)

The views must resolve the slug correctly against the REAL `~/.claude/.rnd/`
tree, not just this fixture. Run from the real `.rnd` root, the audit glob
`*/**/audit.jsonl` matches both on-disk layouts and the slug is the first path
component:

```sh
# .rnd root = dirname of dirname of `rnd-dir.sh --calibration`
duckdb \
  -c "SELECT count(*) FILTER (WHERE file NOT LIKE '%/branches/%') AS legacy_files,
             count(*) FILTER (WHERE file LIKE '%/branches/%')     AS branch_files
      FROM glob('*/**/audit.jsonl')" \
  -c "SELECT count(*) AS audit_rows,
             bool_or(regexp_extract(filename, '^\.?/?([^/]+)/', 1) = 'claude-130cb64f') AS has_dogfood_slug,
             bool_or(filename LIKE '%/branches/%'
                     AND regexp_extract(filename, '^\.?/?([^/]+)/', 1) = 'claude-130cb64f') AS branch_path_resolves_to_slug
      FROM read_csv('claude-130cb64f/**/audit.jsonl',
        columns={'j':'VARCHAR'}, delim=E'\x01', quote='', escape='',
        header=false, auto_detect=false, ignore_errors=true, filename=true)
      WHERE TRY(json_valid(j))"
```

Expected: both `legacy_files` and `branch_files` are `> 0`; `audit_rows > 0`;
`has_dogfood_slug` and `branch_path_resolves_to_slug` are both `true` (a
branch-partitioned path resolves to the slug `claude-130cb64f`, never to the
branch name). The views read via a tolerant `read_csv` raw-line scan filtered
by `WHERE TRY(json_valid(j))`, so historical pretty-printed / truncated audit
files in other slugs are skipped rather than crashing the full-tree read;
`glob()` proves the match without parsing.
