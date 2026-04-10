---
name: rnd-integrate
description: "Run integration and system validation for a verified wave. Merges outputs, runs integration tests, checks for regressions."
user-invocable: false
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
- If no such wave exists, report the current state and use `AskUserQuestion`.

Use `TaskList` to confirm ALL tasks in the specified wave are `completed` (verified).

If any task in the wave is not yet verified, STOP and tell the user which tasks still need verification.

Create a `TaskCreate` entry for the integration itself (e.g., "Integrate wave-1"). Mark it `in_progress`.

## Integration Process

**Spawn an Integrator agent:**

```
Agent({
  description: "Integrate verified wave",
  subagent_type: "rnd-framework:rnd-integrator",
  mode: "bypassPermissions",
  prompt: "Wave: <N>\nRND_DIR: <path>\nVerified tasks: <list>\nFinal wave: <true/false>"
})
```

Do NOT integrate yourself. The Integrator merges verified outputs, runs integration tests, checks for regressions, and produces `$RND_DIR/integration/wave-<N>-report.md` with a SHIP or NO-SHIP verdict.

Summarize integration results. Then use `AskUserQuestion`:

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
