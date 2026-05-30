---
name: rnd-calibration
description: "Use when recording verdict data, detecting false verdicts, or injecting calibration stats into verifier prompts — enables the framework to learn from verification mistakes over time"
user-invocable: false
effort: low
---

# R&D Calibration

## Overview

Track verification verdicts over time so the framework can detect systematic bias — verifiers that pass broken work or fail correct work. Calibration data lives in a simple JSONL file at the project base level.

**Core principle:** A verifier that issues false verdicts is worse than no verifier. Calibration surfaces patterns before they become systemic.

## When to Use

- After any task completes a full build-verify cycle (automated via orchestrator)
- When a manual ground-truth correction is needed (`/rnd-framework:rnd-calibrate`)
- When the orchestrator constructs verifier prompts (inject calibration summary)
- When diagnosing a pipeline that keeps cycling without converging

## JSONL Record Schema

Each completed task appends one record to `calibration.jsonl`:

```json
{
  "task_id": "M1.T03.example-task",
  "sessionId": "20260316-154145-1227",
  "verdict": "PASS",
  "criterionResults": [
    { "criterion": "File exists at path", "result": "PASS" },
    { "criterion": "YAML frontmatter valid", "result": "PASS" }
  ],
  "iterationCount": 2,
  "timestamp": "2026-03-16T15:41:45Z",
  "falseVerdictFlag": null
}
```

**Fields:**

| Field | Type | Notes |
|-------|------|-------|
| `task_id` | string | Task identifier (e.g. `"M1.T03.example-task"`) |
| `sessionId` | string | Session that produced this verdict |
| `verdict` | string | `"PASS"`, `"FAIL"`, `"NEEDS_ITERATION"`, or `"PASS_QUALITY_NEEDS_ITERATION"` |
| `criticality` | string | `"LOW"`, `"NORMAL"`, or `"HIGH"` — the task's criticality tier at the time of the verdict. Used by `lib/calibration.sh` to compute per-tier rolling false-PASS rates for auto-escalation. |
| `criterionResults` | array | Per-criterion `{ criterion, result }` objects |
| `iterationCount` | number | Build-verify cycles required |
| `timestamp` | string | ISO 8601 UTC |
| `falseVerdictFlag` | string or null | Set by detection or manual correction. Values: `"FALSE_PASS"`, `"FALSE_FAIL"`, `"FALSE_PASS_PROXY"`, or `null`. |
| `proxyFor` | string or null | Present only when `falseVerdictFlag` is `"FALSE_PASS_PROXY"`. The `timestamp` value of the original PASS record this proxy links to. |
| `task_type` | string or null | Optional. Rule-based taxonomy tag inferred by the orchestrator from the pre-registration `Intent` and task title. Values: `refactor \| new-feature \| bugfix \| docs \| config \| infra`. Defaults to `infra` on no keyword match. See "task_type Inference Policy" sub-section below. |
| `gateFired` | object or null | Optional. Present when a new reliability gate fired for this task. Shape: `{ "gate": string, "outcome": string, "task_id": string }`. `gate` is one of the four producer gate names (see "gateFired Producer Registry" sub-section). `outcome` is the gate result (e.g., `INVALID_FOUND`, `CLEAN`, `FLAGGED`, `BLOCKED`). `task_id` is the task this gate firing applies to. Append one `gateFired` record per gate firing; multiple gates may fire for a single task. |
| `verification_mode` | string or null | Optional. The mode of verification used to produce this verdict. Allowed values: `property \| prose \| skipped`. Set to `property` when the pre-reg declared `## Properties` and the runner produced a non-skipped result; `skipped` when the property runner detected a missing runtime; `prose` for all other (conventional) verification. Omit entirely for records predating this field. |

### task_type Inference Policy

The orchestrator infers `task_type` from the pre-registration `Intent` field and task title using a keyword-priority list. Match the first rule that fires; default to `infra` on no match.

| task_type | Trigger keywords (match any, case-insensitive) |
|-----------|------------------------------------------------|
| `refactor` | refactor, restructure, rename, reorganize, cleanup, extract, move, split |
| `new-feature` | feature, add, introduce, implement, new, build, create, support |
| `bugfix` | fix, bug, defect, broken, wrong, incorrect, regression, patch |
| `docs` | docs, documentation, readme, changelog, comment, annotate, describe |
| `config` | config, setting, env, environment, flag, toggle, threshold, parameter |
| `infra` | (default — no keyword match, or keywords: infra, scaffold, pipeline, hook, gate, schema, telemetry) |

Rules:
- Match against the concatenation of task title + `Intent` field value.
- First match wins — order in the table above is the evaluation order.
- `infra` is the explicit last-resort default; it also matches on its own keywords for tasks that clearly fall in that category.
- Keyword matching is word-boundary agnostic (substring match is sufficient).

### gateFired Producer Registry

The following gates append `gateFired` records to `calibration.jsonl`. Future gates register here.

| Gate name | Producer | What it records |
|-----------|----------|-----------------|
| `existence_prepass` | `rnd-reality-auditor` | Pre-pass existence check result for a declared external reference |
| `stop_condition_verdict_flip` | orchestrator post-wave check | Detects PASS→FAIL→PASS or FAIL→PASS→FAIL verdict sequences via `audit-scan.sh verdict_history`; outcome `halted` |
| `stop_condition_plan_size` | orchestrator post-plan check | Detects task count exceeding `RND_STOP_PLAN_RATIO × Heuristic ceiling`; outcome `halted` |
| `coverage_gaps_gate` | verifier / SubagentStop enforcement | Records when a pre-reg is missing required coverage sections; outcome `BLOCKED` or `CLEAN` |
| `assumption_unchecked` | verifier / pre-reg discipline check | Records when assumptions lack `Refuted by` evidence; outcome `FLAGGED` or `CLEAN` |

Each gate fires at most once per task per pipeline run. Multiple firings for different tasks produce separate records with distinct `task_id` values.

## Storage Location

**Primary location:** `${CLAUDE_PLUGIN_DATA}/calibration.jsonl`

`CLAUDE_PLUGIN_DATA` is set by Claude Code for persistent plugin data that survives plugin updates. Use it when available.

**Fallback:** If `CLAUDE_PLUGIN_DATA` is not set, use `--calibration` to get the slug-root path:

Calibration lives at the slug root — above the `branches/` partition — so it accumulates across all branches:

```
~/.claude/.rnd/<dirname>-<hash>/       # Slug root (calibration lives here)
├── calibration.jsonl                  # Append-only verdict log (cross-branch)
└── branches/
    └── main/                          # Branch-scoped base ($BASE_DIR from --base)
        ├── roadmap.md
        ├── project-facts.md
        └── sessions/
            └── 20260316-154145-1227/  # $RND_DIR (per pipeline run)
```

`rnd-dir.sh --calibration` returns `<slug-root>/calibration.jsonl` directly (no `/branches/` component), regardless of the current branch.

Append a record:
```bash
CALIB_FILE="${CLAUDE_PLUGIN_DATA:-$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --calibration)}"
echo '{"task_id":...}' >> "$CALIB_FILE"
```

**Why cross-session?** Calibration data accumulates across sessions. Storing it inside a session would isolate it to one run, defeating the purpose.

## Automatic False-Verdict Detection

The orchestrator scans `calibration.jsonl` after each pipeline run for patterns that indicate a false verdict. When detected, it sets `falseVerdictFlag` on the affected record.

**False PASS patterns:**

- A task received PASS but integration failed for that task's component — indicates the verifier approved broken work.
- A task received PASS but a post-ship bug was traced back to it — indicates the verifier missed a defect.

Set `falseVerdictFlag: "FALSE_PASS"` on the record.

**False FAIL patterns:**

- A task received FAIL or NEEDS_ITERATION, the builder made a trivial one-line fix (diff shows ≤3 lines changed), and the next round produced PASS — indicates the verifier rejected correct work.

Set `falseVerdictFlag: "FALSE_FAIL"` on the record.

### FALSE_PASS_PROXY Recording Rule

When a task with a previous PASS verdict in the same session receives a subsequent FAIL or NEEDS_ITERATION verdict on the same `task_id`, the orchestrator appends a new record with `falseVerdictFlag: "FALSE_PASS_PROXY"` linking to the original PASS via `proxyFor: <originalRecordTimestamp>`. This is a pragmatic measurable signal for closed-loop calibration: it captures the observable evidence that an earlier PASS verdict was incorrect without requiring a post-ship bug or integration failure to confirm it.

The proxy record carries the same `task_id` and `criticality` as the original, so `lib/calibration.sh false_pass_rate <tier>` counts it alongside confirmed `FALSE_PASS` records when computing the rolling rate. T12 wires the orchestrator to follow this rule when iterating tasks.

Example proxy record:

```json
{
  "task_id": "M1.T05.example-task",
  "sessionId": "20260516-122648-8c7c8d3c",
  "verdict": "NEEDS_ITERATION",
  "criticality": "MEDIUM",
  "timestamp": "2026-05-16T14:00:00Z",
  "falseVerdictFlag": "FALSE_PASS_PROXY",
  "proxyFor": "2026-05-16T13:30:00Z"
}
```

## Manual Ground-Truth Recording

When automatic detection cannot determine the correct verdict (ambiguous iteration, external cause), use `/rnd-framework:rnd-calibrate` to record a manual correction.

The command prompts for:
1. Task ID to correct
2. Correct verdict (`PASS` or `FAIL`)
3. Reason (free-text)

It writes a correction record to `calibration.jsonl`:

```json
{
  "task_id": "M1.T05.example-task",
  "sessionId": "20260316-154145-1227",
  "correction": "FALSE_PASS",
  "reason": "Integration test revealed missing null check",
  "timestamp": "2026-03-16T18:00:00Z"
}
```

Correction records have a `correction` field instead of `verdict`, making them distinguishable from primary verdict records.

## Stats Injection Into Verifier Prompts

Before running the verification phase, the orchestrator reads `calibration.jsonl` and computes basic stats, then prepends a summary to the verification context:

```
Calibration summary for this project (last 30 verdicts):
- False PASS rate: 2/15 (13%)
- False FAIL rate: 1/15 (7%)
- Most-failed criterion: "YAML frontmatter valid" (3 failures)
- Escalation rate (first-pass non-PASS): 4/10 (40%)
- First-pass overturned rate: 1/4 (25%)
```

**What the verification phase does with this:** No special action required. The summary is contextual — it raises alertness for known problem areas without overriding the information barrier or the verification phase's independent judgment.

**Keep it simple:** Aggregate counts only. No per-verifier breakdown, no dashboards, no trend charts. A plain read over the JSONL file is sufficient.

## Related Skills

- `rnd-framework:rnd-verification` — The verification process that produces the verdicts being calibrated
- `rnd-framework:rnd-orchestration` — Orchestrator reads calibration stats and injects them into verifier prompts
- `rnd-framework:rnd-iteration` — False FAILs inflate iteration counts; calibration identifies this pattern
