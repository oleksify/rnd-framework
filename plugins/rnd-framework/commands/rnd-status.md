---
description: "Show the current status of the R&D pipeline: which tasks are planned, built, verified, integrated, or stuck in iteration."
effort: low
disallowed-tools: ["Edit", "Write"]
---

# R&D Framework: Status

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

If `$RND_DIR` does not exist or contains no artifacts (no `protocol.md`, no `builds/`, no `verifications/`), report: "No active pipeline. Start one with `/rnd-framework:rnd-start <task>`."

### Status determination

Derive task status by scanning artifact directories. Read `$RND_DIR/protocol.md` for the task list, then check:

1. `$RND_DIR/integration/wave-<N>-report.md` — if exists and contains SHIP → **integrated**
2. `$RND_DIR/verifications/T<id>-pass-receipt.json` — if exists → **verified**
3. `$RND_DIR/verifications/T<id>-verification.md` — if exists, read verdict:
   - NEEDS_ITERATION → **iterating**
4. `$RND_DIR/builds/T<id>-manifest.md` — if exists and non-empty → **built**
5. Otherwise → **planned**

Supplement with:
- `$RND_DIR/iteration-log.md` for iteration history and cycle counts
- `TaskList` for blocked/in-progress metadata

### Status icon mapping

Map task statuses to display icons:

- **📋 Planned** — status `planned` (or `pending` in TaskList fallback)
- **🔨 Built** — status `built`
- **✅ Verified** — status `verified`
- **🔄 Iterating** — status `iterating`
- **⚠️ Escalated** — status `iterating` with iteration count >= 3 (check `iteration-log.md`)
- **🚀 Integrated** — status `integrated`
- **❌ Failed** — status `failed`

Display as a table:

```
Wave | Task ID | Name                    | Status        | Iterations
-----|---------|-------------------------|---------------|----------
  1  | T1      | Design API contracts    | ✅ Verified   | 0
  2  | T2      | OAuth callback handler  | 🔄 Iterating  | 1/3
  2  | T3      | Token storage service   | 🔨 Built      | —
  2  | T4      | Login UI component      | 📋 Planned    | —
  3  | T5      | End-to-end auth flow    | 📋 Planned    | —
```

Also show:
- Current wave being worked on
- Any blocked tasks (from `TaskList` blockedBy data) — resolve `#<n>` blockedBy IDs to pipeline IDs by matching against task `metadata.pipelineId` or by extracting the `T<n>` prefix from the blocked task's subject; never display raw `#<n>` internal IDs to the user
- Iteration log summary (which tasks needed rework and why)
- Overall progress percentage

After displaying the status, use `AskUserQuestion` to suggest the logical next action based on current state:
- If tasks are planned but not built: "Build next wave (Recommended)", "Review plan"
- If tasks are built but not verified: "Verify built tasks (Recommended)", "Review build artifacts"
- If tasks are verified and ready for integration: "Integrate wave (Recommended)", "Review verification reports"
- If tasks are stuck in iteration: "Continue iteration (Recommended)", "Re-plan failing tasks", "Skip and proceed"

## Calibration trends (flag: --calibration-trends)

When invoked with `--calibration-trends`, skip the task-status table and instead print the rolling false-PASS rate for each criticality tier, followed by any tier-escalation events from the current session.

### Data source: slug-root calibration.jsonl

`calibration.jsonl` lives at the un-partitioned slug root — above the `branches/` tree — so it accumulates records across every session and branch. Resolve it via the canonical resolver:

```bash
calib_file=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --calibration)
```

To verify the file exists before reading, use `find`:

```bash
found=$(find "$(dirname "$calib_file")" -maxdepth 1 -name "calibration.jsonl" 2>/dev/null | head -1)
```

**If `calibration.jsonl` is absent** (no records have been written yet), print:

```
No calibration data yet. Run a full pipeline wave to populate trends.
```

and exit 0. Do not print per-tier rate lines when there is no data.

### Per-tier rate output

For each tier in order LOW, MEDIUM, HIGH, print one line:

```
LOW: false-PASS X% (over N records)
MEDIUM: false-PASS X% (over N records)
HIGH: false-PASS X% (over N records)
```

Where:
- `X%` is `false_pass_rate <tier>` multiplied by 100, formatted as an integer percentage (e.g. `0.30` → `30%`).
- `N` is the count of records in the rolling window for that tier (last 10 records by default).
- The rate is obtained by calling `lib/calibration.sh false_pass_rate <tier>` via the plugin root:
  ```bash
  rate=$("${CLAUDE_PLUGIN_ROOT}/lib/calibration.sh" false_pass_rate LOW)
  ```
  `calibration.sh` reads from the slug-root file automatically — no per-session scoping is applied.

### Tier-escalation events

After the rate lines, scan the active session's `$RND_DIR/audit.jsonl` for lines where `.event == "tier_escalated"`. For each match, print one line:

```
  <task_id>: <tool>
```

where `task_id` and `tool` are the fields from the audit event (the `tool` field carries the tier-transition string such as `MEDIUM->HIGH`).

If `audit.jsonl` is absent, empty, or contains no `tier_escalated` records, print:

```
No tier escalations in this session.
```

### Example output

```
LOW: false-PASS 0% (over 0 records)
MEDIUM: false-PASS 30% (over 10 records)
HIGH: false-PASS 10% (over 10 records)

Tier escalations this session:
  T7: MEDIUM->HIGH
```
