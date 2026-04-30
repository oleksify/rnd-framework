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

### Status determination

Derive task status by scanning artifact directories. Read `$RND_DIR/plan.md` for the task list, then check:

1. `$RND_DIR/integration/wave-<N>-report.md` — if exists and contains SHIP → **integrated**
2. `$RND_DIR/verifications/T<id>-pass-receipt.json` — if exists → **verified**
3. `$RND_DIR/verifications/T<id>-verification.md` — if exists, read verdict:
   - NEEDS ITERATION → **iterating**
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
