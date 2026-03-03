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
- **NEEDS ITERATION:** Keep the task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` to track the cycle count. Extract ONLY the feedback section from the verification report. Do NOT extract the Verifier's internal reasoning. Pass feedback to the Builder. Track in `$RND_DIR/iteration-log.md`. Max 3 iterations.
- **FAIL:** Same as NEEDS ITERATION.
- After iteration, re-verify with the same information barrier rules.

Summarize verification results to the user: which tasks passed, which need iteration, key findings. Then use `AskUserQuestion`:

If all tasks PASS:
- "Proceed to integration (Recommended)" — run `/rnd-framework:integrate` for this wave
- "Review verification reports" — inspect reports before proceeding

If any tasks NEED ITERATION:
- "Iterate on failing tasks (Recommended)" — re-build and re-verify failing tasks
- "Re-plan failing tasks" — send back to Planner for re-decomposition
- "Skip failing tasks and continue" — proceed with passing tasks only

If iteration budget (3 cycles) is exhausted:
- "Re-plan this task" — decompose differently
- "Skip and continue (Recommended)" — proceed without this task
- "Stop pipeline" — halt for manual intervention
