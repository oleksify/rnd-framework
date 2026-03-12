---
description: "Run independent multi-judge verification on a built task. Two verifier agents check output against pre-registered criteria independently; a tiebreaker resolves disagreement."
argument-hint: "<task ID like T3, or 'wave-2' to verify all tasks in a wave>"
---

# R&D Framework: Verify

Invoke skill: `rnd-framework:rnd-multi-judge`

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/plan.md`. Check `TaskList` to confirm which tasks are built and ready for verification.

## CRITICAL: Information Barrier Enforcement

> **Note on `bypassPermissions` and read-gate:** When spawning verifiers with `mode: "bypassPermissions"`, the `read-gate` hook may be suppressed. The information barrier is enforced through three layers: (1) the `read-gate` hook blocks self-assessment reads at the tool level, (2) the pre-flight check below catches files before prompt assembly, (3) each verifier agent runs a startup self-check to detect leaked content. Do not rely on any single layer — all three must hold.

### Pre-Flight Check

Run this sanity check **once** before assembling any judge prompts. It applies to all judges — initial judges A and B and the tiebreaker:

```bash
SA_FILES=$(ls "$RND_DIR/builds/"*self-assessment* 2>/dev/null || true)
if [ -n "$SA_FILES" ]; then
  echo "INFO-BARRIER: The following files must NOT appear in any verifier prompt:"
  echo "$SA_FILES"
fi
```

Review the list. Cross-check every prompt you assemble — none of these paths or their contents may appear in any judge prompt, including the tiebreaker.

### Prompt Assembly

When spawning any verifier agent (Agent tool with `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "bypassPermissions"`), you MUST:

**INCLUDE:**
- The task's pre-registration document (copy from `$RND_DIR/plan.md`)
- Paths to the Builder's code and test files
- Relevant codebase context
- **For the tiebreaker only:** both Judge A and Judge B reports (`$RND_DIR/verifications/T<id>-judge-a.md` and `$RND_DIR/verifications/T<id>-judge-b.md`)

**EXCLUDE — DO NOT PASS (applies to ALL judges including the tiebreaker):**
- Any `$RND_DIR/builds/T*-self-assessment.md` files
- The Builder's reasoning or chain-of-thought
- Any notes about "what to look for" or "known issues"

After assembling each prompt, scan it for the substring `self-assessment`. If found, do NOT spawn the verifier — strip the offending content and re-assemble.

This barrier is the core of the framework. If violated, verification becomes rubber-stamping.

## Execution

Use `TaskUpdate` to mark target tasks as `in_progress` before spawning verifiers.

If $ARGUMENTS is a task ID: verify that one task.
If $ARGUMENTS is a wave: verify all tasks in the wave.
If $ARGUMENTS is "all": use `TaskList` to find all built but unverified tasks.

For each task, follow the multi-judge protocol:

### Step 1 — Spawn 2 Independent Judges (parallel)

Spawn Judge A and Judge B simultaneously using the Agent tool. Both use `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "bypassPermissions"`.

Each judge receives:
- The pre-registration document
- The Builder's code and test files

Neither judge's prompt includes the other judge's report. The two judges run with no knowledge of each other.

After each judge completes, the orchestrator saves the returned report to:
- Judge A: `$RND_DIR/verifications/T<id>-judge-a.md`
- Judge B: `$RND_DIR/verifications/T<id>-judge-b.md`

Multiple tasks in a wave can each have their own parallel judge pairs — all 2×N judges may run simultaneously if resources allow.

### Step 2 — Compare Verdicts

After both judges complete, read their reports and extract the `Overall Verdict` from each.

**When both judges agree** (same verdict), that verdict is the final verdict. Skip to Step 4.

| Judge A | Judge B | Final Verdict |
|---------|---------|---------------|
| PASS    | PASS    | PASS          |
| FAIL    | FAIL    | FAIL          |
| NEEDS ITERATION | NEEDS ITERATION | NEEDS ITERATION |

**When judges disagree** (any split — PASS/FAIL, PASS/NEEDS ITERATION, FAIL/NEEDS ITERATION), proceed to Step 3.

### Step 3 — Tiebreaker Judge (on disagreement only)

Spawn a third verifier as tiebreaker using `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "bypassPermissions"`.

The tiebreaker receives:
- The pre-registration document
- The Builder's code and test files
- Judge A's full report (`$RND_DIR/verifications/T<id>-judge-a.md`)
- Judge B's full report (`$RND_DIR/verifications/T<id>-judge-b.md`)

The tiebreaker does NOT receive self-assessment files. The same EXCLUDE rules apply.

After the tiebreaker completes, the orchestrator saves the returned report to: `$RND_DIR/verifications/T<id>-tiebreaker.md`

The tiebreaker's verdict is the final verdict.

### Step 4 — Save Aggregated Report

Save the aggregated result to `$RND_DIR/verifications/T<id>-verification.md` following the format from `rnd-framework:rnd-multi-judge`:

```markdown
# Verification Report: T<id>

## Judge A Report

[Full contents of Judge A's per-criterion results and verdict]

---

## Judge B Report

[Full contents of Judge B's per-criterion results and verdict]

---

## Tiebreaker Report (if applicable)

[Full contents of tiebreaker's report, or omit this section if both judges agreed]

---

## Final Consensus Verdict: PASS | FAIL | NEEDS ITERATION

**Consensus method:** Both judges agreed | Tiebreaker required — [Judge A verdict] vs [Judge B verdict]

## Feedback (if not PASS)

[Consolidated actionable feedback from the deciding report(s). Describe WHAT is wrong. Do NOT suggest fixes.]
```

## After Verification

Process each task's consensus verdict:
- **PASS:** Use `TaskUpdate` to mark the task `completed`.
- **NEEDS ITERATION:** A clear, isolated failure the Builder can fix. Keep the task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` to track the cycle count. Extract ONLY the feedback section from the aggregated verification report — do NOT include any judge's internal reasoning. Pass feedback to the Builder. Track in `$RND_DIR/iteration-log.md`. Max 3 iterations. After iteration, re-verify with the same information barrier rules and multi-judge protocol.
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
