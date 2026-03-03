---
description: "Run the Build phase for a specific task or wave from the existing RND plan."
argument-hint: "<task ID like T3 or wave number like wave-2>"
---

# R&D Framework: Build

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/plan.md`. Check `TaskList` to identify current task states.

If $ARGUMENTS specifies a task ID (e.g., "T3"):
- Use `TaskUpdate` to mark the task `in_progress`.
- Spawn one `rnd-framework:rnd-builder` agent for that specific task with `mode: "bypassPermissions"`.

If $ARGUMENTS specifies a wave (e.g., "wave-2"):
- Use `TaskUpdate` to mark ALL tasks in the wave as `in_progress`.
- Spawn `rnd-framework:rnd-builder` agents in parallel for ALL tasks in that wave, each with `mode: "bypassPermissions"`.

If $ARGUMENTS is "next":
- Use `TaskList` to find the next wave where all tasks are `pending` and unblocked.
- Mark those tasks `in_progress` and build them in parallel, each with `mode: "bypassPermissions"`.

After build completes, confirm all outputs exist and tests pass locally (Gate 2). Use `TaskUpdate` to mark each successfully built task as `completed`.

Summarize build results to the user: which tasks completed, any deviations from plan, any escalations. Then use `AskUserQuestion` with options:
- "Proceed to verification (Recommended)" — run `/rnd-framework:verify` for this wave
- "Review build artifacts first" — inspect code and tests before verification
- "Build next wave" — skip verification for now and build the next wave

Do NOT auto-proceed to verification without user confirmation.
