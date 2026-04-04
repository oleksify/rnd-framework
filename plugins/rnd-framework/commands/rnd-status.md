---
description: "Show the current status of the R&D pipeline: which tasks are planned, built, verified, integrated, or stuck in iteration."
effort: low
---

# R&D Framework: Status

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

If `$RND_DIR` does not exist or contains no artifacts (no `plan.md`, no `builds/`, no `verifications/`), report: "No active pipeline. Start one with `/rnd-framework:rnd-start <task>`."

### Primary source: pipeline-state.json

If `$RND_DIR/pipeline-state.json` exists, read it and derive task statuses directly from the `tasks` object. Each task's `status` field maps to the display icons below. This is the authoritative source — it is updated at every phase gate and survives context compaction.

Supplement with `$RND_DIR` artifact details for richer context:
- Check `$RND_DIR/iteration-log.md` for iteration history and cycle counts
- Check `$RND_DIR/verifications/` for verdict details
- Check `$RND_DIR/integration/` for SHIP/NO-SHIP verdicts

### Fallback: TaskList + artifact scanning

If `$RND_DIR/pipeline-state.json` does not exist (older pipeline session or pipeline started before this feature), fall back to the previous approach: use `TaskList` as the primary source and supplement with artifact directory scanning.

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
- Any blocked tasks (from `TaskList` blockedBy data)
- Iteration log summary (which tasks needed rework and why)
- Overall progress percentage

After displaying the status, use `AskUserQuestion` to suggest the logical next action based on current state:
- If tasks are planned but not built: "Build next wave (Recommended)", "Review plan"
- If tasks are built but not verified: "Verify built tasks (Recommended)", "Review build artifacts"
- If tasks are verified and ready for integration: "Integrate wave (Recommended)", "Review verification reports"
- If tasks are stuck in iteration: "Continue iteration (Recommended)", "Re-plan failing tasks", "Skip and proceed"
