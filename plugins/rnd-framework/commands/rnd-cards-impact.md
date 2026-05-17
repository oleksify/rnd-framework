---
description: "Compare iterations-to-PASS distributions pre/post a rollout date, broken down per task_type, and print a verdict (improved | no-change | regressed) per type."
argument-hint: "--since=<ISO-date> [--per-type-min=<N>]"
effort: low
---

# R&D Framework: Cards Impact Analysis

Compare how the number of iterations needed to reach PASS changed before and after a rollout date,
broken down by task type. Useful for measuring whether a process change, tooling update, or card
library addition actually reduced rework.

## Arguments

- `--since=<ISO date>` — **Required.** The rollout date. Records whose task started before this
  date are "pre-rollout"; records on or after are "post-rollout". Accepts any ISO 8601 date or
  datetime string (e.g. `2026-03-01` or `2026-03-01T00:00:00Z`).

- `--per-type-min=<N>` — Optional. Minimum number of tasks on each side of the split to emit a
  meaningful verdict. Defaults to **3**. Buckets with fewer than N samples on either side emit
  `insufficient-data` instead of a verdict, preventing false signal from small samples.

## Usage

```bash
"${CLAUDE_PLUGIN_ROOT}/lib/rnd-cards-impact.sh" --since=2026-03-01
"${CLAUDE_PLUGIN_ROOT}/lib/rnd-cards-impact.sh" --since=2026-03-01 --per-type-min=5
```

## Metric definition

**Iterations-to-PASS** for a task: the count of `NEEDS_ITERATION` records for that `taskId` that
appear before the first `PASS` record. Tasks that never reached PASS are excluded entirely. The
task is assigned to the pre or post bucket based on the timestamp of its _first_ calibration
record (i.e., when the task started, not when it finished).

**Data source:** `calibration.jsonl`, read via `CLAUDE_PLUGIN_DATA` if set, otherwise via
`lib/rnd-dir.sh --calibration`. Records without a `timestamp` field are excluded. Records without
a `task_type` field default to `infra` (consistent with the orchestration task_type inference
policy: default when no keyword matches).

## Output format

A markdown table with one row per task_type:

```
| task_type    | pre-N | pre-median | pre-p75 | post-N | post-median | post-p75 | verdict           |
|--------------|-------|------------|---------|--------|-------------|----------|-------------------|
| refactor     |    12 |          2 |       3 |     10 |           0 |        1 | improved          |
| new-feature  |     5 |          1 |       2 |      4 |           1 |        2 | no-change         |
| bugfix       |     0 |         — |      — |      0 |          — |      — | insufficient-data |
```

**Columns:**
- `pre-N` / `post-N` — number of tasks in each bucket
- `pre-median` / `post-median` — median iterations-to-PASS (50th percentile)
- `pre-p75` / `post-p75` — 75th percentile iterations-to-PASS
- `verdict` — improvement signal (see below)

**Percentile computation:** sort the per-task counts ascending; median is the element at index
`floor((N−1) × 0.5)`; p75 is the element at index `floor((N−1) × 0.75)`.

## Verdict thresholds

Verdicts are based on the **median delta**, with a threshold of 0.5 to suppress noise:

| Condition | Verdict |
|-----------|---------|
| `post_median < pre_median − 0.5` | `improved` |
| `post_median > pre_median + 0.5` | `regressed` |
| otherwise | `no-change` |
| either side has fewer than `--per-type-min` tasks | `insufficient-data` |

The 0.5 threshold means a one-unit drop in median iterations (e.g., from 2 to 1) is required to
signal improvement. Equal medians always produce `no-change`.

## Task types

Reports on all six canonical task types in order:
`refactor` | `new-feature` | `bugfix` | `docs` | `config` | `infra`

## Invocation

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
"${CLAUDE_PLUGIN_ROOT}/lib/rnd-cards-impact.sh" $ARGUMENTS
```

Parse `$ARGUMENTS` for `--since` and `--per-type-min`. Pass them directly to the lib script.
If `--since` is absent, print a usage error and exit.
