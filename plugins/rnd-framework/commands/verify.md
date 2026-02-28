---
description: "Run independent verification on a built task. The Verifier checks output against pre-registered criteria without seeing the Builder's reasoning."
argument-hint: "<task ID like T3, or 'wave-2' to verify all tasks in a wave>"
---

# R&D Framework: Verify

Read the plan from `.rnd/plan.md`.

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

If $ARGUMENTS is a task ID: verify that one task.
If $ARGUMENTS is a wave: verify all tasks in the wave (can be parallel — verifiers are independent).
If $ARGUMENTS is "all": verify all unverified built tasks.

## After Verification

- **PASS:** Mark task as verified. Report to user.
- **NEEDS ITERATION:** Extract ONLY the feedback section from the verification report. Do NOT extract the Verifier's internal reasoning. Pass feedback to the Builder. Track in `.rnd/iteration-log.md`. Max 3 iterations.
- After iteration, re-verify with the same information barrier rules.
