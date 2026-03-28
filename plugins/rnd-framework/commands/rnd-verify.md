---
description: "Run criticality-conditional verification on a built task. Verifies against pre-registered criteria with information barrier."
argument-hint: "<task ID like T3, or 'wave-2' to verify all tasks in a wave>"
effort: high
---

# R&D Framework: Verify

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/plan.md`. Check `TaskList` to confirm which tasks are built and ready for verification.

## CRITICAL: Information Barrier Enforcement

You MUST NOT read `$RND_DIR/builds/T<id>-self-assessment.md` files during verification. The `read-gate.sh` hook blocks these reads mechanically. You wrote the self-assessment during the build phase, but during verification you must assess work purely against the pre-registered spec.

### Pre-Flight Check

Run this sanity check **once** before verification:

```bash
SA_FILES=$(ls "$RND_DIR/builds/"*self-assessment* 2>/dev/null || true)
if [ -n "$SA_FILES" ]; then
  echo "INFO-BARRIER: The following files must NOT be read during verification:"
  echo "$SA_FILES"
fi
```

## Execution

Invoke `rnd-framework:rnd-verification` to load verification discipline.

Use `TaskUpdate` to mark target tasks as `in_progress` before verifying.

If $ARGUMENTS is a task ID: verify that one task.
If $ARGUMENTS is a wave: verify all tasks in the wave.
If $ARGUMENTS is "all": find all built but unverified tasks.

For each task:

### Step 1 — Read Criticality

Read the task's `Criticality` field from its pre-registration in `$RND_DIR/plan.md`. If absent, treat as NORMAL.

### Step 2 — Verify

1. **Read the pre-registration document.** Understand intent, approach, and success criteria.

2. **Write independent experiment tests** — before reviewing your build code, write one experiment test per criterion. Derive from spec text only. Save to `$RND_DIR/verifications/T<id>-experiments/`.

3. **Run experiments against the built code.** Record raw output verbatim.

4. **Run the built tests and compare.** Check test adequacy per criterion.

5. **Code inspection and failure mode analysis.** Scan for boundary cases, error handling, race conditions, external contract conformance. Cross-reference build manifest evidence.

6. **Cross-criterion sweep.** Before writing any verdicts: look for systemic patterns, shared root causes, fragile passes.

7. **Produce verification report.** Save to `$RND_DIR/verifications/T<id>-verification.md`.

**Iteration budget by criticality:**

| Criticality | Max iterations |
|-------------|---------------|
| LOW         | 2             |
| NORMAL      | 3             |
| HIGH        | 5             |

## After Verification

Process each task's verdict:
- **PASS:** Use `TaskUpdate` to mark the task `completed`.
- **PASS (quality: NEEDS ITERATION):** Mark `completed`. Save quality feedback to `$RND_DIR/verifications/T<id>-quality-feedback.md`. Does NOT block integration.
- **NEEDS ITERATION:** Keep `in_progress`. Track with `metadata: {"iteration": N}`. Extract ONLY the feedback section — do NOT include your internal reasoning. Save feedback for the build phase.
- **FAIL:** Route to re-planning.

Summarize verification results. Then use `AskUserQuestion`/`AskUser`:

If all tasks PASS or PASS (quality: NEEDS ITERATION):
- "Proceed to integration (Recommended)" — run `/rnd-framework:rnd-integrate`
- "Iterate on quality first"
- "Review verification reports"

If any tasks got NEEDS ITERATION:
- "Iterate on failing tasks (Recommended)" — re-build and re-verify
- "Skip failing tasks and continue"

If any tasks got FAIL:
- "Re-plan failing tasks (Recommended)"
- "Iterate anyway"
- "Skip failing tasks and continue"

If iteration budget is exhausted:
- "Re-plan this task (Recommended)"
- "Skip and continue"
- "Stop pipeline"
