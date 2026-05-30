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

From this fixture directory (`lib/stats/fixtures/`). Every view reads the
`RND_DOGFOOD_SLUGS` env var to classify slugs into the `dogfood` segment —
without it, all rows classify as `feature` and the expected tables below will
not reproduce. Set the env var first:

```sh
export RND_DOGFOOD_SLUGS="claude-130cb64f"

duckdb -c ".read ../shape_distribution.sql"        -c "SELECT * FROM shape_distribution ORDER BY segment, shape"
duckdb -c ".read ../per_shape_fail_rate.sql"       -c "SELECT * FROM per_shape_fail_rate ORDER BY segment, shape"
duckdb -c ".read ../iteration_depth.sql"           -c "SELECT * FROM iteration_depth ORDER BY segment, iteration_count"
duckdb -c ".read ../iteration_reasons.sql"         -c "SELECT * FROM iteration_reasons ORDER BY segment, reason_verdict"
duckdb -c ".read ../self_fail_vs_verdict_gap.sql"  -c "SELECT * FROM self_fail_vs_verdict_gap ORDER BY segment"
duckdb -c ".read ../fail_rate_over_time.sql"       -c "SELECT * FROM fail_rate_over_time ORDER BY segment, week"
duckdb -c ".read ../backfill.sql"                  -c "SELECT * FROM backfill ORDER BY segment, task_id"
duckdb -c ".read ../drift_watch.sql"               -c "SELECT segment, session_ordinal, session_id, iter_metric, replan_count, iter_slope, replan_slope, window_n FROM drift_watch ORDER BY segment, session_ordinal"
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
  - `claude-130cb64f/calibration.jsonl` — its verdicts (incl. the correction record and 7 drift-watch sessions)
  - `claude-130cb64f/sessions/s-df-1/audit.jsonl` — legacy layout
  - `claude-130cb64f/branches/main/sessions/s-df-2/audit.jsonl` — branch-partitioned layout
  - `claude-130cb64f/sessions/s-df-hist/audit.jsonl` — legacy layout (historical)
  - `claude-130cb64f/sessions/s-df-3/audit.jsonl` — legacy layout (2 replan_started events; no shape/self-assessment facts)
  - `claude-130cb64f/branches/main/sessions/s-df-4/audit.jsonl` — branch-partitioned layout (2 replan_started events)
  - `claude-130cb64f/sessions/s-df-5/audit.jsonl` — legacy layout (1 replan_started event)
  - `claude-130cb64f/branches/main/sessions/s-df-6/audit.jsonl` — branch-partitioned layout (1 replan_started event)
  - sessions s-df-7, s-df-8, s-df-9 — calibration records only; no audit.jsonl (replan_count = 0)
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

Drift-watch sessions (calibration records only; no shape/self-assessment events in audit so Views 1–4 are unaffected). Sessions s-df-3/s-df-4/s-df-5/s-df-6 carry `replan_started` events; s-df-7/s-df-8/s-df-9 have no audit.jsonl (replan_count = 0 via COALESCE). `session_id` spelling is mixed intentionally — some records use camelCase `sessionId`, others use snake_case `session_id` — to exercise the COALESCE in drift_watch.sql:

| task_id       | slug            | segment | session  | session_id key | iterationCount | replan_count | verdict timestamp    |
|---------------|-----------------|---------|----------|----------------|----------------|--------------|----------------------|
| M3.T-01.drift | claude-130cb64f | dogfood | s-df-3   | sessionId      | 8              | 2            | 2026-05-15T12:00:00Z |
| M3.T-02.drift | claude-130cb64f | dogfood | s-df-4   | session_id     | 7              | 2            | 2026-05-17T12:00:00Z |
| M3.T-03.drift | claude-130cb64f | dogfood | s-df-5   | session_id     | 6              | 1            | 2026-05-18T12:00:00Z |
| M3.T-04.drift | claude-130cb64f | dogfood | s-df-6   | sessionId      | 5              | 1            | 2026-05-20T12:00:00Z |
| M3.T-05.drift | claude-130cb64f | dogfood | s-df-7   | session_id     | 3              | 0            | 2026-05-22T12:00:00Z |
| M3.T-06.drift | claude-130cb64f | dogfood | s-df-8   | sessionId      | 2              | 0            | 2026-05-24T12:00:00Z |
| M3.T-07.drift | claude-130cb64f | dogfood | s-df-9   | session_id     | 1              | 0            | 2026-05-26T12:00:00Z |

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

Histogram of iteration depth per task, by segment. The view tolerates two
calibration-record shapes via `COALESCE(stored_iter, first_pass_rn, total_records)`:
when records carry a stored `iterationCount` field (this fixture's shape) the
stored value is used directly; otherwise depth is derived as the count of
records up to and including the first PASS in chronological order.

Historical tasks contribute to the histogram: `M0.T-h.setup` (dogfood, count=0)
adds to dogfood/0; `M0.T-i.setup` (feature, count=2) adds a new feature/2 bucket.

The 7 drift-watch sessions (M3.T-01 through M3.T-07) also contribute to the
dogfood histogram with iterationCount values 8, 7, 6, 5, 3, 2, 1. These extend
the histogram into high-count buckets.

| segment | iteration_count | task_count |
|---------|-----------------|------------|
| dogfood | 0               | 2          |
| dogfood | 1               | 3          |
| dogfood | 2               | 2          |
| dogfood | 3               | 2          |
| dogfood | 5               | 1          |
| dogfood | 6               | 1          |
| dogfood | 7               | 1          |
| dogfood | 8               | 1          |
| feature | 0               | 1          |
| feature | 1               | 1          |
| feature | 2               | 1          |

## View 3a — `iteration_reasons`

Distribution of non-PASS verdicts in calibration, by segment. Each non-PASS
verdict is a reason the build-verify cycle did not terminate cleanly at that
record. Companion to `iteration_depth` (which counts cycles).

In this fixture only `FAIL` appears as a non-PASS verdict (the verdicts
`NEEDS_ITERATION` and `PASS_QUALITY_NEEDS_ITERATION` exist in the schema but
are not present in fixture data). Three FAIL records contribute: `M1.T-b.crud`
and `M1.T-d.schema` in dogfood, `M0.T-i.setup` in feature. The correction
record on `M1.T-b.crud` carries no `verdict` field and is excluded.

| segment | reason_verdict | occurrences |
|---------|----------------|-------------|
| dogfood | FAIL           | 2           |
| feature | FAIL           | 1           |

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
- Week `2026-05-11` contains the 2026-05-15 and 2026-05-17 drift-watch verdicts (s-df-3, s-df-4).
- Week `2026-05-18` contains the 2026-05-18, 2026-05-20, 2026-05-22, and 2026-05-24 drift-watch verdicts (s-df-5, s-df-6, s-df-7, s-df-8).
- Week `2026-05-25` contains the 2026-05-26 drift-watch verdict (s-df-9).

| segment | week                | task_count | fail_count | fail_rate |
|---------|---------------------|------------|------------|-----------|
| dogfood | 2026-03-09 00:00:00 | 1          | 0          | 0.0       |
| dogfood | 2026-04-27 00:00:00 | 3          | 1          | 0.3333    |
| dogfood | 2026-05-04 00:00:00 | 2          | 1          | 0.5       |
| dogfood | 2026-05-11 00:00:00 | 2          | 0          | 0.0       |
| dogfood | 2026-05-18 00:00:00 | 4          | 0          | 0.0       |
| dogfood | 2026-05-25 00:00:00 | 1          | 0          | 0.0       |
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
| M3.T-01.drift | s-df-3     | PASS    | 8               | NORMAL      | dogfood | NULL  | NULL       | iter-pass      |
| M3.T-02.drift | NULL       | PASS    | 7               | NORMAL      | dogfood | NULL  | NULL       | iter-pass      |
| M3.T-03.drift | NULL       | PASS    | 6               | NORMAL      | dogfood | NULL  | NULL       | iter-pass      |
| M3.T-04.drift | s-df-6     | PASS    | 5               | NORMAL      | dogfood | NULL  | NULL       | iter-pass      |
| M3.T-05.drift | NULL       | PASS    | 3               | NORMAL      | dogfood | NULL  | NULL       | iter-pass      |
| M3.T-06.drift | s-df-8     | PASS    | 2               | NORMAL      | dogfood | NULL  | NULL       | iter-pass      |
| M3.T-07.drift | NULL       | PASS    | 1               | NORMAL      | dogfood | NULL  | NULL       | iter-pass      |
| M0.T-i.setup  | s-ft-hist  | FAIL    | 2               | NORMAL      | feature | NULL  | NULL       | abandoned      |
| M2.T-f.crud   | s-ft-1     | PASS    | 0               | NORMAL      | feature | NULL  | NULL       | first-try-pass |
| M2.T-g.docs   | s-ft-1     | PASS    | 1               | LOW         | feature | NULL  | NULL       | iter-pass      |

Historical records are `M0.T-h.setup` (dogfood) and `M0.T-i.setup` (feature).
Both have `shape = NULL` and `confidence = NULL` because their sessions contain
no planner-emitted shape/confidence audit events.

The 7 drift-watch tasks (M3.T-01 through M3.T-07) also have `shape = NULL` and
`confidence = NULL` for the same reason — their sessions carry only calibration
and replan_started records, no planner-emitted shape/confidence events.
`session_id` is NULL for the four records that use the snake_case `session_id`
key in calibration.jsonl: `backfill.sql` reads only `$.sessionId` (camelCase),
so the snake_case records produce NULL in this column. This is expected behavior
— only `drift_watch.sql` COALESCEs both spellings.

---

## View 7 — `drift_watch`

Per-session iteration load and replan frequency, with 10-row rolling linear
regression slopes (`regr_slope` over `ROWS BETWEEN 9 PRECEDING AND CURRENT ROW`).
`iter_slope` and `replan_slope` are `nan` (not NULL) when the window contains
fewer than 2 rows; they are non-NULL, non-nan starting from the second row where
two distinct x values exist.

The dogfood segment has 10 sessions (s-df-hist + s-df-1 + s-df-2 + s-df-3
through s-df-9) so `window_n = 10` for the last row (s-df-9, ordinal 10), which
is the first row with a full-window slope. The `iter_metric` values peak at
ordinal 4 (s-df-3, iter=8) then fall through ordinal 10 (s-df-9, iter=1),
producing a negative `iter_slope` at ordinal 10. Similarly, `replan_count` rises
at ordinals 4–5 then falls to 0, producing a negative `replan_slope` at
ordinal 10.

The feature segment has 2 sessions (s-ft-hist and s-ft-1) and therefore has no
full-window row (max window_n = 2).

Sessions s-df-4, s-df-5, s-df-7, s-df-9 use snake_case `session_id` in their
calibration records. `drift_watch.sql` COALESCEs both spellings, so these
sessions are identified correctly and their `session_id` values appear in the
output as expected.

| segment | session_ordinal | session_id | iter_metric | replan_count |     iter_slope      |     replan_slope      | window_n |
|---------|----------------:|------------|------------:|-------------:|--------------------:|----------------------:|---------:|
| dogfood | 1               | s-df-hist  | 0.0         | 0            | nan                 | nan                   | 1        |
| dogfood | 2               | s-df-1     | 3.0         | 0            | 3.0                 | 0.0                   | 2        |
| dogfood | 3               | s-df-2     | 4.0         | 0            | 2.0                 | 0.0                   | 3        |
| dogfood | 4               | s-df-3     | 8.0         | 2            | 2.5                 | 0.6                   | 4        |
| dogfood | 5               | s-df-4     | 7.0         | 2            | 1.9                 | 0.6                   | 5        |
| dogfood | 6               | s-df-5     | 6.0         | 1            | 1.3142857142857145  | 0.37142857142857144   | 6        |
| dogfood | 7               | s-df-6     | 5.0         | 1            | 0.8571428571428571  | 0.25                  | 7        |
| dogfood | 8               | s-df-7     | 3.0         | 0            | 0.42857142857142855 | 0.09523809523809523   | 8        |
| dogfood | 9               | s-df-8     | 2.0         | 0            | 0.13333333333333333 | 0.01666666666666667   | 9        |
| dogfood | 10              | s-df-9     | 1.0         | 0            | -0.0787878787878788 | -0.024242424242424235 | 10       |
| feature | 1               | s-ft-hist  | 2.0         | 0            | nan                 | nan                   | 1        |
| feature | 2               | s-ft-1     | 1.0         | 0            | -1.0                | 0.0                   | 2        |

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

## View 8 — `post_review_findings`

Per-shape post-pipeline-review findings, by segment. Reads `*/post-review.jsonl`
(one file per slug root). Input grain is per-finding; the view aggregates to
per-(session, shape) before counting so a session with multiple findings on the
same shape is counted once, not inflated.

Fixture facts:

- `claude-130cb64f/post-review.jsonl` (dogfood):
  - Session `s-df-rev-1`: two findings on `crud`, both `verifier_said_PASS:true, review_found:true`
    → collapses to one (session,shape) row: has_finding=true, pass_but_found=true
  - Session `s-df-rev-2`: one row on `crud`, `verifier_said_PASS:false, review_found:false` (clean)
    → collapses to one (session,shape) row: has_finding=false, pass_but_found=false
  → dogfood/crud: review_count=2, finding_count=1 (one dirty session), gap_count=1

- `acme-widgets-7f3a1b2c/post-review.jsonl` (feature):
  - Session `s-ft-rev-1`: one finding on `docs`, `verifier_said_PASS:true, review_found:true`
    → collapses to one (session,shape) row: has_finding=true, pass_but_found=true
  → feature/docs: review_count=1, finding_count=1, gap_count=1

FM2 proof: s-df-rev-1 has 2 finding rows → `finding_count = 1` (one dirty session),
not 2. `count(*) FROM post_review_findings` = 2, which equals the distinct
(segment, shape) pair count — never inflated by the per-finding input grain.

```sh
export RND_DOGFOOD_SLUGS="claude-130cb64f"
duckdb -c ".read ../post_review_findings.sql" -c "SELECT * FROM post_review_findings ORDER BY segment, shape"
```

| segment | shape | review_count | finding_count | gap_count |
|---------|-------|--------------|---------------|-----------|
| dogfood | crud  | 2            | 1             | 1         |
| feature | docs  | 1            | 1             | 1         |

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
