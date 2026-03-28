---
description: "Show the current status of the R&D pipeline: which tasks are planned, built, verified, integrated, or stuck in iteration."
effort: low
---

# R&D Framework: Status

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

If `$RND_DIR` does not exist or contains no artifacts (no `plan.md`, no `builds/`, no `verifications/`), report: "No active pipeline. Start one with `/rnd-framework:rnd-start <task>` or `/rnd-framework:rnd-quick <task>`."

Otherwise, use `TaskList` as the **primary status source** to get an overview of all tasks, their states, owners, and blockers.

Then supplement with `$RND_DIR` artifact details for richer context:
- Check `$RND_DIR/iteration-log.md` for iteration history
- Check `$RND_DIR/verifications/` for verdict details
- Check `$RND_DIR/integration/` for SHIP/NO-SHIP verdicts

Map task states to pipeline phases:

- **📋 Planned** — Task is `pending` with no build artifacts
- **🔨 Built** — Task is `completed` and `$RND_DIR/builds/T<id>-manifest.md` exists, but no verification report yet
- **🔍 In Verification** — Task is `in_progress` during verify phase
- **✅ Verified** — Task is `completed` with PASS verdict in `$RND_DIR/verifications/T<id>-verification.md`
- **🔄 Iterating** — Task is `in_progress` with `iteration` metadata > 0
- **⚠️ Escalated** — Iteration metadata shows 3+ cycles
- **🚀 Integrated** — Part of a SHIP verdict in `$RND_DIR/integration/`

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

After displaying the status, use `AskUserQuestion`/`AskUser` to suggest the logical next action based on current state:
- If tasks are planned but not built: "Build next wave (Recommended)", "Review plan"
- If tasks are built but not verified: "Verify built tasks (Recommended)", "Review build artifacts"
- If tasks are verified and ready for integration: "Integrate wave (Recommended)", "Review verification reports"
- If tasks are stuck in iteration: "Continue iteration (Recommended)", "Re-plan failing tasks", "Skip and proceed"
