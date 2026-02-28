---
description: "Run integration and system validation for a verified wave. Merges outputs, runs integration tests, checks for regressions."
argument-hint: "<wave number like wave-2, or 'final' for system validation>"
---

# R&D Framework: Integrate

Read the plan from `.rnd/plan.md`. Use `TaskList` to confirm ALL tasks in the specified wave are `completed` (verified).

If any task in the wave is not yet verified, STOP and tell the user which tasks still need verification (reference their task IDs from `TaskList`).

Create a `TaskCreate` entry for the integration itself (e.g., "Integrate wave-1") with `activeForm: "Integrating wave-1"`. Mark it `in_progress` via `TaskUpdate`.

Spawn the `rnd-integrator` agent for the wave.

If $ARGUMENTS is "final", also run full system validation against the original task requirements.

Report the SHIP/NO-SHIP verdict to the user:
- **SHIP:** Use `TaskUpdate` to mark the integration task `completed`.
- **NO-SHIP:** Keep the integration task `in_progress`. Identify failing integration points and route back to relevant builders.
