---
name: rnd-verify
description: "Run criticality-conditional verification on a built task. Verifies against pre-registered criteria with information barrier."
user-invocable: false
effort: high
---

# R&D Framework: Verify

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/protocol.md` (and the assertions from `$RND_DIR/validation-contract.md`). Check `TaskList` to confirm which tasks are built and ready for verification.

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

Use `TaskUpdate` to mark target tasks as `in_progress` before verifying.

If $ARGUMENTS is a task ID: verify that one task.
If $ARGUMENTS is a wave: verify all tasks in the wave.
If $ARGUMENTS is "all": find all built but unverified tasks.

**Wave-batched spawn:** Spawn one Verifier agent per wave (not per task). The Verifier receives all task pre-registrations for the wave and returns a `wave-N-verdict-map.json` plus per-task artifacts. Criticality drives the per-agent model boost (see `rnd-framework:rnd-orchestration`); there is no parallel-judge mode.

```
Agent({
  description: "Verify wave <N>",
  subagent_type: "rnd-framework:rnd-verifier",
  mode: "acceptEdits",
  prompt: "Wave: <N>\nTasks in wave: T<id1>, T<id2>, ...\nRND_DIR: <path>\n<paste all task pre-registrations sliced from validation-contract.md>"
})
```

Do NOT verify tasks yourself. The Verifier agent independently writes experiment tests, runs them, inspects code, and produces a per-task verdict map. Its failure-mode sweep includes External contract conformance — the Verifier queries the real external systems (APIs, schemas, services) to confirm the Builder's claims rather than trusting the manifest.

On PASS: the Verifier writes `T<id>-pass-receipt.json` to `$RND_DIR/verifications/` — no prose report is produced.
On FAIL/NEEDS_ITERATION/PASS_QUALITY_NEEDS_ITERATION: the Verifier produces a `T<id>-verification.md` prose report.

## After Verification

Read `$RND_DIR/verifications/wave-<N>-verdict-map.json`. Process each task's verdict:
- **PASS:** Use `TaskUpdate` to mark the task `completed`.
- **PASS_QUALITY_NEEDS_ITERATION:** Mark `completed`. Save quality feedback to `$RND_DIR/verifications/T<id>-quality-feedback.md`. Does NOT block integration.
- **NEEDS_ITERATION:** Keep `in_progress`. Track with `metadata: {"iteration": N}`. Extract ONLY the feedback section — do NOT include your internal reasoning. Save feedback for the build phase.
- **FAIL:** Route to re-planning.

Summarize verification results. Then use `AskUserQuestion`:

If all tasks PASS or PASS_QUALITY_NEEDS_ITERATION:
- "Proceed to integration (Recommended)" — run `/rnd-framework:rnd-integrate`
- "Iterate on quality first"
- "Review verification reports"

If any tasks got NEEDS_ITERATION:
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
