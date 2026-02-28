---
description: "Run integration and system validation for a verified wave. Merges outputs, runs integration tests, checks for regressions."
argument-hint: "<wave number like wave-2, or 'final' for system validation>"
---

# R&D Framework: Integrate

Read the plan from `.rnd/plan.md`. Confirm ALL tasks in the specified wave have PASS verdicts in `.rnd/verifications/`.

If any task in the wave is not yet verified, STOP and tell the user which tasks still need verification.

Spawn the `rnd-integrator` agent for the wave.

If $ARGUMENTS is "final", also run full system validation against the original task requirements.

Report the SHIP/NO-SHIP verdict to the user.
