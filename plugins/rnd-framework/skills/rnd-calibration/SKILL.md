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
- When a manual ground-truth correction is needed (`/rnd-framework:calibrate`)
- When the orchestrator constructs verifier prompts (inject calibration summary)
- When diagnosing a pipeline that keeps cycling without converging

## JSONL Record Schema

Each completed task appends one record to `calibration.jsonl`:

```json
{
  "taskId": "T3",
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
| `taskId` | string | Task identifier (e.g. `"T3"`) |
| `sessionId` | string | Session that produced this verdict |
| `verdict` | string | `"PASS"`, `"FAIL"`, or `"NEEDS_ITERATION"` |
| `criterionResults` | array | Per-criterion `{ criterion, result }` objects |
| `iterationCount` | number | Build-verify cycles required |
| `timestamp` | string | ISO 8601 UTC |
| `falseVerdictFlag` | string or null | Set by detection or manual correction |

## Storage Location

**Primary location:** `${CLAUDE_PLUGIN_DATA}/calibration.jsonl`

`CLAUDE_PLUGIN_DATA` is set by Claude Code for persistent plugin data that survives plugin updates. Use it when available.

**Fallback ($BASE_DIR):** If `CLAUDE_PLUGIN_DATA` is not set, fall back to the project base directory:

```bash
BASE_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --base)
```

The project base sits alongside the `sessions/` directory — not inside any session:

```
~/.claude/.rnd/<dirname>-<hash>/       # Project base ($BASE_DIR fallback)
├── calibration.jsonl                  # Append-only verdict log
└── sessions/
    └── 20260316-154145-1227/          # $RND_DIR (per pipeline run)
```

Append a record: `echo '{"taskId":...}' >> "${CLAUDE_PLUGIN_DATA:-$BASE_DIR}/calibration.jsonl"`

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

## Manual Ground-Truth Recording

When automatic detection cannot determine the correct verdict (ambiguous iteration, external cause), use `/rnd-framework:calibrate` to record a manual correction.

The command prompts for:
1. Task ID to correct
2. Correct verdict (`PASS` or `FAIL`)
3. Reason (free-text)

It writes a correction record to `calibration.jsonl`:

```json
{
  "taskId": "T5",
  "sessionId": "20260316-154145-1227",
  "correction": "FALSE_PASS",
  "reason": "Integration test revealed missing null check",
  "timestamp": "2026-03-16T18:00:00Z"
}
```

Correction records have a `correction` field instead of `verdict`, making them distinguishable from primary verdict records.

## Stats Injection Into Verifier Prompts

Before spawning a verifier agent, the orchestrator reads `calibration.jsonl` and computes basic stats, then prepends a summary to the verifier prompt:

```
Calibration summary for this project (last 30 verdicts):
- False PASS rate: 2/15 (13%)
- False FAIL rate: 1/15 (7%)
- Most-failed criterion: "YAML frontmatter valid" (3 failures)
```

**What the verifier does with this:** No special action required. The summary is contextual — it raises alertness for known problem areas without overriding the information barrier or the verifier's independent judgment.

**Keep it simple:** Aggregate counts only. No per-verifier breakdown, no dashboards, no trend charts. A plain read over the JSONL file is sufficient.

## Related Skills

- `rnd-framework:rnd-verification` — The verification process that produces the verdicts being calibrated
- `rnd-framework:rnd-orchestration` — Orchestrator reads calibration stats and injects them into verifier prompts
- `rnd-framework:rnd-iteration` — False FAILs inflate iteration counts; calibration identifies this pattern
