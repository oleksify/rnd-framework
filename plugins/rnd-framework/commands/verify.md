---
description: "Run criticality-conditional verification on a built task. LOW/NORMAL tasks use a single verifier; HIGH tasks use multi-judge consensus (two verifiers + optional tiebreaker)."
argument-hint: "<task ID like T3, or 'wave-2' to verify all tasks in a wave>"
model: opus
effort: high
---

# R&D Framework: Verify

For HIGH criticality tasks, invoke skill: `rnd-framework:rnd-multi-judge`

Determine the RND artifacts directory:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

Read the plan from `$RND_DIR/plan.md`. Check `TaskList` to confirm which tasks are built and ready for verification.

## CRITICAL: Information Barrier Enforcement

> **Note on `bypassPermissions` and read-gate:** Verifier agents run with `permissionMode: bypassPermissions` declared in their frontmatter, which may suppress the `read-gate` hook. The information barrier is enforced through three layers: (1) the `read-gate` hook blocks self-assessment reads at the tool level, (2) the pre-flight check below catches files before prompt assembly, (3) each verifier agent runs a startup self-check to detect leaked content. Do not rely on any single layer — all three must hold.

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

When spawning any verifier agent (Agent tool with `subagent_type: "rnd-framework:rnd-verifier"`), you MUST:

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

For each task:

### Step 1 — Read Criticality

Read the task's `Criticality` field from its pre-registration document in `$RND_DIR/plan.md`. If the field is absent or omitted, treat it as NORMAL.

### Step 2 — Route by Criticality

**If Criticality is LOW or NORMAL (or omitted):**

Spawn a single verifier agent using the Agent tool with `subagent_type: "rnd-framework:rnd-verifier"`. The agent receives:
- The pre-registration document
- The Builder's code and test files

After the agent returns its report as text output, the orchestrator saves the returned report directly to `$RND_DIR/verifications/T<id>-verification.md`. The report is the final verdict — no consensus logic, no tiebreaker.

**If Criticality is HIGH:**

Invoke `rnd-framework:rnd-multi-judge` for the full protocol. Summary: spawn Judge A and Judge B simultaneously; if they agree their verdict is final, if they disagree spawn a tiebreaker (save to `T<id>-tiebreaker.md`). Save the aggregated report (judges + tiebreaker if used, plus **Consensus method** notation) to `$RND_DIR/verifications/T<id>-verification.md`.

Multiple tasks in a wave can run their verifier agents simultaneously if resources allow.

**Iteration budget by criticality:**

| Criticality | Max iterations |
|-------------|---------------|
| LOW         | 2             |
| NORMAL (or omitted) | 3    |
| HIGH        | 5             |

## After Verification

Process each task's consensus verdict:
- **PASS:** Use `TaskUpdate` to mark the task `completed`.
- **PASS (quality: NEEDS ITERATION):** Correctness is fully met; quality tier has feedback. Use `TaskUpdate` to mark the task `completed`. Save the quality feedback section from the aggregated verification report to `$RND_DIR/verifications/T<id>-quality-feedback.md`. Quality-tier failures do NOT block integration — they are deferred for a non-blocking iteration round after integration succeeds.
- **NEEDS ITERATION:** A clear, isolated Correctness failure the Builder can fix. Keep the task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": N}` to track the cycle count. Extract ONLY the feedback section from the aggregated verification report — do NOT include any judge's internal reasoning. Pass feedback to the Builder. Track in `$RND_DIR/iteration-log.md`. Max iterations per criticality (LOW=2, NORMAL=3, HIGH=5). After iteration, re-verify with the same information barrier rules and criticality-conditional routing.
- **FAIL:** Multiple unmet Correctness criteria or no clear fix path — the task needs re-decomposition, not iteration. Do NOT pass to the Builder for iteration. Present this as a re-planning candidate.

Summarize verification results to the user: which tasks passed fully, which passed with quality feedback (quality: NEEDS ITERATION), which need Correctness iteration, which failed outright. Then use `AskUserQuestion`:

If all tasks PASS or PASS (quality: NEEDS ITERATION) (no Correctness failures):
- "Proceed to integration (Recommended)" — run `/rnd-framework:integrate`; quality-tier feedback deferred to post-integration
- "Iterate on quality first" — address quality-tier feedback before integration
- "Review verification reports" — inspect reports before proceeding

If any tasks got NEEDS ITERATION (Correctness failure, but none FAIL):
- "Iterate on failing tasks (Recommended)" — re-build and re-verify
- "Skip failing tasks and continue" — skip and proceed with passing tasks only (see skip procedure below)
If any tasks got FAIL:
- "Re-plan failing tasks (Recommended)" — send back to Planner for re-decomposition
- "Iterate anyway" — treat as NEEDS ITERATION
- "Skip failing tasks and continue" — skip and proceed (see skip procedure below)
If iteration budget is exhausted (LOW after 2, NORMAL after 3, HIGH after 5):
- "Re-plan this task (Recommended)" — decompose differently
- "Skip and continue" — see skip procedure below
- "Stop pipeline" — halt for manual intervention

**Quality iteration round (after integration SHIP):** After integration succeeds, if any task has `quality: NEEDS ITERATION` feedback recorded in `$RND_DIR/verifications/T<id>-quality-feedback.md`, use `AskUserQuestion`: "Iterate on quality now" (spawn Builders with quality feedback, then re-verify) or "Defer quality iteration (Recommended)" (note feedback, address in a future pipeline run).

## Skip Procedure

When the user chooses to skip a failing task:

1. Mark the task: `TaskUpdate` with `status: "completed"` and `metadata: {"skipped": true, "reason": "<why>"}`.
2. **Check downstream dependencies.** Use `TaskList` to find any tasks that had this task in their `blockedBy`. Warn the user about each dependent task and ask whether to also skip it, proceed anyway, or re-plan.
3. When integrating, explicitly list skipped tasks so the integrator can exclude them from merge and note them in the report.
