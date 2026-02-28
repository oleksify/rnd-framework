---
description: "Run the Build phase for a specific task or wave from the existing RND plan."
argument-hint: "<task ID like T3 or wave number like wave-2>"
---

# R&D Framework: Build

Read the plan from `.rnd/plan.md`. Check `TaskList` to identify current task states.

If $ARGUMENTS specifies a task ID (e.g., "T3"):
- Use `TaskUpdate` to mark the task `in_progress`.
- Spawn one `rnd-builder` agent for that specific task.

If $ARGUMENTS specifies a wave (e.g., "wave-2"):
- Use `TaskUpdate` to mark ALL tasks in the wave as `in_progress`.
- Spawn `rnd-builder` agents in parallel for ALL tasks in that wave.

If $ARGUMENTS is "next":
- Use `TaskList` to find the next wave where all tasks are `pending` and unblocked.
- Mark those tasks `in_progress` and build them in parallel.

After build completes, confirm all outputs exist and tests pass locally (Gate 2). Use `TaskUpdate` to mark each successfully built task as `completed`.

Do NOT auto-proceed to verification — let the user trigger `/rnd-framework:verify` when ready.
