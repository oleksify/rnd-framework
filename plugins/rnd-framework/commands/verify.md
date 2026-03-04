---
description: "Run independent verification on a built task. The Verifier checks output against pre-registered criteria without seeing the Builder's reasoning."
argument-hint: "<task ID like T3, or 'wave-2' to verify all tasks in a wave>"
---

# R&D Framework: Verify

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/plan.md`. Check `TaskList` to confirm which tasks are built and ready for verification.

## CRITICAL: Information Barrier Enforcement

When spawning the `rnd-framework:rnd-verifier` agent, you MUST:

**INCLUDE:**
- The task's pre-registration document (copy from `$RND_DIR/plan.md`)
- Paths to the Builder's code and test files
- Relevant codebase context

**EXCLUDE — DO NOT PASS:**
- Any `$RND_DIR/builds/T*-self-assessment.md` files
- The Builder's reasoning or chain-of-thought
- Any notes about "what to look for" or "known issues"

This barrier is the core of the framework. If violated, verification becomes rubber-stamping.

## Execution

Use `TaskUpdate` to mark target tasks as `in_progress` before spawning verifiers.

Spawn all `rnd-framework:rnd-verifier` agents with `mode: "bypassPermissions"`.

If $ARGUMENTS is a task ID: verify that one task.
If $ARGUMENTS is a wave: verify all tasks in the wave (can be parallel — verifiers are independent).
If $ARGUMENTS is "all": use `TaskList` to find all built but unverified tasks.

## After Verification

Process each task's verdict:
- **PASS:** Use `TaskUpdate` to mark the task `completed`.
- **NEEDS ITERATION:** A clear, isolated failure the Builder can fix. Keep the task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` to track the cycle count. Extract ONLY the feedback section from the verification report — do NOT include the Verifier's internal reasoning. Pass feedback to the Builder. Track in `$RND_DIR/iteration-log.md`. Max 3 iterations. After iteration, re-verify with the same information barrier rules.
- **FAIL:** Multiple unmet criteria or no clear fix path — the task needs re-decomposition, not iteration. Do NOT pass to the Builder for iteration. Present this as a re-planning candidate.

Summarize verification results to the user: which tasks passed, which need iteration, which failed outright. Then use `AskUserQuestion`:

If all tasks PASS:
- "Proceed to integration (Recommended)" — run `/rnd-framework:integrate` for this wave
- "Review verification reports" — inspect reports before proceeding

If any tasks got NEEDS ITERATION (but none FAIL):
- "Iterate on failing tasks (Recommended)" — re-build and re-verify
- "Skip failing tasks and continue" — skip and proceed with passing tasks only (see skip procedure below)

If any tasks got FAIL:
- "Re-plan failing tasks (Recommended)" — send back to Planner for re-decomposition
- "Iterate anyway" — treat as NEEDS ITERATION (use only if you disagree with the Verifier's severity)
- "Skip failing tasks and continue" — skip and proceed (see skip procedure below)

If iteration budget (3 cycles) is exhausted:
- "Re-plan this task (Recommended)" — decompose differently
- "Skip and continue" — skip this task and proceed (see skip procedure below)
- "Stop pipeline" — halt for manual intervention

## Skip Procedure

When the user chooses to skip a failing task:

1. Mark the task: `TaskUpdate` with `status: "completed"` and `metadata: {"skipped": true, "reason": "<why>"}`.
2. **Check downstream dependencies.** Use `TaskList` to find any tasks that had this task in their `blockedBy`. Warn the user about each dependent task and ask whether to also skip it, proceed anyway, or re-plan.
3. When integrating, explicitly list skipped tasks so the integrator can exclude them from merge and note them in the report.
