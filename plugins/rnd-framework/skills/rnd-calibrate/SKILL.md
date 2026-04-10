---
name: rnd-calibrate
description: "Record a manual ground-truth verdict correction for a completed task. Reads the original verdict from the verification report and appends a correction record to calibration.jsonl."
user-invocable: false
effort: low
---

# R&D Framework: Calibrate

Invoke skill: `rnd-framework:rnd-calibration`

## Step 1: Parse Arguments

Parse `$ARGUMENTS` by splitting on whitespace:

- **`session-id`** — first token (e.g. `20260316-154145-1227`)
- **`task-id`** — second token (e.g. `T3`)
- **`true-verdict`** — third token: `PASS` or `FAIL`
- **`reason`** — remainder of the string (optional free-text)

If any of `session-id`, `task-id`, or `true-verdict` are missing, use `AskUserQuestion`:

> "Please provide: session-id, task-id, and true-verdict (PASS or FAIL)."

## Step 2: Read the Original Verdict

Get the project base directory and locate the verification report:

```bash
BASE_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --base)
VERDICT_FILE="${BASE_DIR}/sessions/<session-id>/verifications/<task-id>-verification.md"
```

Read `$VERDICT_FILE`. If it does not exist, display an error:

> "No verification report found at `$VERDICT_FILE`. Check the session-id and task-id."

Extract the verdict line (e.g. `## Verdict: PASS`) from the report to show the original verdict alongside the correction.

## Step 3: Append Correction Record

Determine the calibration file path. Use `CLAUDE_PLUGIN_DATA` if set; fall back to `$BASE_DIR` (computed from `rnd-dir.sh --base`) otherwise:

```bash
CALIB_FILE="${CLAUDE_PLUGIN_DATA:-$BASE_DIR}/calibration.jsonl"
```

Build a correction record and append it to `$CALIB_FILE`:

```json
{
  "taskId": "<task-id>",
  "sessionId": "<session-id>",
  "correction": "<FALSE_PASS or FALSE_FAIL>",
  "reason": "<reason>",
  "timestamp": "<ISO 8601 UTC>"
}
```

Set `correction` to `"FALSE_PASS"` when `true-verdict` is `FAIL` (original was PASS), and `"FALSE_FAIL"` when `true-verdict` is `PASS` (original was FAIL). If the original verdict matches `true-verdict`, record `correction: "CONFIRMED"`.

Append the JSON object as a single line to `$CALIB_FILE`.

## Step 4: Confirm

Display a brief confirmation:

> "Correction recorded: `<task-id>` in session `<session-id>` — original verdict overridden with `<true-verdict>`. Record appended to `calibration.jsonl`."
