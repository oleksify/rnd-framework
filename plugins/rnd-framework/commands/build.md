---
description: "Run the Build phase for a specific task or wave from the existing RND plan."
argument-hint: "<task ID like T3 or wave number like wave-2>"
---

# R&D Framework: Build

Read the plan from `.rnd/plan.md`.

If $ARGUMENTS specifies a task ID (e.g., "T3"):
- Spawn one `rnd-builder` agent for that specific task.

If $ARGUMENTS specifies a wave (e.g., "wave-2"):
- Spawn `rnd-builder` agents in parallel for ALL tasks in that wave.

If $ARGUMENTS is "next":
- Find the next unbuilt wave and build all its tasks in parallel.

After build completes, confirm all outputs exist and tests pass locally (Gate 2).

Do NOT auto-proceed to verification — let the user trigger `/rnd-framework:verify` when ready.
