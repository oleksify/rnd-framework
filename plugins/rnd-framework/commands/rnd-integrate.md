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
- If found, proceed to integrate that wave.
- If no such wave exists, report the current state and use `AskUserQuestion`/`AskUser`.

Use `TaskList` to confirm ALL tasks in the specified wave are `completed` (verified).

If any task in the wave is not yet verified, STOP and tell the user which tasks still need verification.

Create a `TaskCreate` entry for the integration itself (e.g., "Integrate wave-1"). Mark it `in_progress`.

## Integration Process

Invoke `rnd-framework:rnd-integration` to load integration discipline. Perform integration yourself:

1. Confirm all tasks in the wave are verified (check `$RND_DIR/verifications/`).
2. Ensure all code integrates cleanly — no merge conflicts, interfaces match, imports correct.
3. Run integration tests — do modules communicate correctly? Are API contracts honored?
4. If $ARGUMENTS is "final", run full system validation against the original task requirements.
5. Run the existing project test suite to check for regressions.
6. Save integration report to `$RND_DIR/integration/wave-<N>-report.md`.
7. Issue SHIP or NO-SHIP verdict.

Summarize integration results. Then use `AskUserQuestion`/`AskUser`:

If **SHIP:**
- Mark the integration task `completed`.
- "Commit changes (Recommended)"
- "Review integration report"
- "Proceed to next wave" (if more waves remain)

If **NO-SHIP:**
- Keep the integration task `in_progress`.
- "Fix failing integration points (Recommended)"
- "Re-plan affected tasks"
- "Stop pipeline"
