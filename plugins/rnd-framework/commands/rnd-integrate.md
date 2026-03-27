---
description: "Run integration and system validation for a verified wave. Merges outputs, runs integration tests, checks for regressions."
argument-hint: "<wave number like wave-2, or 'final' for system validation>"
effort: medium
---

# R&D Framework: Integrate

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/plan.md`.

If $ARGUMENTS is empty (user ran `/rnd-framework:rnd-integrate` with no arguments):
- Use `TaskList` to find the most recent wave where all tasks are `completed` (verified) and no integration report yet exists in `$RND_DIR/integration/`.
- If found, proceed to integrate that wave (treating it as the $ARGUMENTS value).
- If no such wave exists (either nothing is verified yet, or all verified waves are already integrated), report the current state and use `AskUserQuestion` to ask the user what to do next.

Use `TaskList` to confirm ALL tasks in the specified wave are `completed` (verified).

If any task in the wave is not yet verified, STOP and tell the user which tasks still need verification (reference their task IDs from `TaskList`).

Create a `TaskCreate` entry for the integration itself (e.g., "Integrate wave-1") with `activeForm: "Integrating wave-1"`. Mark it `in_progress` via `TaskUpdate`.

Spawn an agent using the Agent tool with `subagent_type: "rnd-framework:rnd-integrator"` for the wave.

If $ARGUMENTS is "final", also run full system validation against the original task requirements.

Summarize integration results to the user. Then use `AskUserQuestion`:

If **SHIP:**
- Use `TaskUpdate` to mark the integration task `completed`.
- "Commit changes (Recommended)" — stage and commit all changes from this wave
- "Review integration report" — inspect the full report before proceeding
- "Proceed to next wave" — if more waves remain, start building the next one

If **NO-SHIP:**
- Keep the integration task `in_progress`.
- "Fix failing integration points (Recommended)" — identify failures and route back to relevant builders
- "Re-plan affected tasks" — send failing tasks back to the Planner for re-decomposition
- "Stop pipeline" — halt for manual intervention
