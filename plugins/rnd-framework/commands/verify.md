---
description: "Run independent verification on a built task. The Verifier checks output against pre-registered criteria without seeing the Builder's reasoning."
argument-hint: "<task ID like T3, or 'wave-2' to verify all tasks in a wave>"
---

# R&D Framework: Verify

Read the plan from `.rnd/plan.md`. Check `TaskList` to confirm which tasks are built and ready for verification.

## CRITICAL: Information Barrier Enforcement

When spawning the `rnd-verifier` agent, you MUST:

**INCLUDE:**
- The task's pre-registration document (copy from `.rnd/plan.md`)
- Paths to the Builder's code and test files
- Relevant codebase context

**EXCLUDE — DO NOT PASS:**
- Any `.rnd/builds/T*-self-assessment.md` files
- The Builder's reasoning or chain-of-thought
- Any notes about "what to look for" or "known issues"

This barrier is the core of the framework. If violated, verification becomes rubber-stamping.

## Execution

Use `TaskUpdate` to mark target tasks as `in_progress` before spawning verifiers.

If $ARGUMENTS is a task ID: verify that one task.
If $ARGUMENTS is a wave: verify all tasks in the wave (can be parallel — verifiers are independent).
If $ARGUMENTS is "all": use `TaskList` to find all built but unverified tasks.

## After Verification

- **PASS:** Use `TaskUpdate` to mark the task `completed`. Report to user.
- **NEEDS ITERATION:** Keep the task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` to track the cycle count. Extract ONLY the feedback section from the verification report. Do NOT extract the Verifier's internal reasoning. Pass feedback to the Builder. Track in `.rnd/iteration-log.md`. Max 3 iterations.
- **FAIL:** Same as NEEDS ITERATION. If iteration budget (3 cycles) is exhausted, report to user for re-planning.
- After iteration, re-verify with the same information barrier rules.
