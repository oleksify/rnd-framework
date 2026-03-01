---
description: "Start the R&D orchestration framework for a complex task. Runs the full pipeline: Plan → Schedule → Build → Verify → Integrate."
argument-hint: "<description of the feature, refactor, or bug fix>"
---

# R&D Framework: Full Pipeline

You are orchestrating a complex coding task using the R&D framework — a scientific-method pipeline. Follow the phases below in strict order. Use subagents for parallelizable work.

## CRITICAL: No Polling

**Never use `sleep`, polling loops, or manual file checks to wait for subagents.** The Agent tool is blocking — it returns only when the subagent finishes. Trust the tool. Spawn agents and process their results when they return. Do not write bash commands to poll `$RND_DIR` for progress.

## Setup

Determine the RND artifacts directory and create its structure:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

Use `$RND_DIR` for all artifact paths below. Pass `RND_DIR` to all spawned agents.

Use `TeamCreate` to create a team named `rnd-pipeline` with a description matching the task. This team coordinates all agents for the pipeline run.

## Phase 1: Plan

Spawn the `rnd-planner` agent with the task description: $ARGUMENTS

Wait for the planner to produce `$RND_DIR/plan.md` with:
- Task tree
- Pre-registration documents (with testable success criteria)
- Dependency matrix
- Execution schedule (waves)

**Gate 1:** Review the plan. Every criterion must be empirically verifiable — a skeptical Verifier must be able to produce a true/false result from evidence alone. Criteria like "works correctly", "handles errors", or "is performant" are automatic rejections. Send back to planner until every criterion specifies an observable outcome.

**After Gate 1 passes:** Summarize the plan to the user: how many tasks, how many waves, key architectural decisions. Then use `AskUserQuestion` with options:
- "Approve plan and auto-continue (Recommended)" — approve and run the full pipeline automatically, pausing only for escalations (iteration budget exhaustion, NO-SHIP verdicts, final completion)
- "Approve plan and start building" — proceed to Phase 2 with manual gates at each phase boundary
- "Request plan revisions" — send feedback to the planner for changes
- "Add more tasks" — extend the plan before building

If the user selects "Approve plan and auto-continue", set **auto-continue mode = ON** for the remainder of this pipeline run. This skips happy-path `AskUserQuestion` gates in Phases 2, 3, and 5, proceeding with the recommended action automatically. Escalation gates (iteration budget exhaustion, NO-SHIP, final completion) are always preserved regardless of mode.

> **Token awareness:** Auto-continue works best with standard iteration budgets (max 3 per task). The pipeline will still pause at budget exhaustion and NO-SHIP verdicts, so runaway token usage is bounded. For very large plans (5+ tasks), consider running with manual gates to review intermediate results.

Once approved, create a `TaskCreate` entry for each task in the plan. Set `subject` to the task name, `description` to the pre-registration content, and `activeForm` to the present-continuous form (e.g., "Building OAuth handler"). Use `addBlockedBy` on each task to mirror the dependency matrix from the plan — if T3 depends on T1, then T3's `addBlockedBy` should include T1's task ID.

## Phase 2: Build (per wave)

For each wave in the execution schedule:

1. **Mark tasks as started:** Use `TaskUpdate` to set each task in the wave to `in_progress`.

2. **Parallel tasks within a wave:** Spawn one `rnd-builder` subagent per task as a **teammate** using the `Agent` tool with `team_name: "rnd-pipeline"`. They can run in parallel since tasks within a wave have no cross-dependencies.

3. **Wait for all builders in the wave to complete.** Builders report completion via `SendMessage`.

4. **Gate 2:** Confirm each builder produced code, tests, artifacts, and self-assessment. On pass, use `TaskUpdate` to mark each task as `completed`.

**After Gate 2:** Summarize build results to the user: which tasks completed, any deviations from plan, any escalations.

If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to verification (Phase 3).

Otherwise, use `AskUserQuestion` with options:
- "Proceed to verification (Recommended)" — spawn Verifiers for this wave
- "Review build artifacts first" — let the user inspect code before verification

## Phase 3: Verify (per task)

For each completed task in the wave:

1. Spawn an `rnd-verifier` subagent as a **teammate** with `team_name: "rnd-pipeline"`. Pass it ONLY:
   - The task's pre-registration document (from `$RND_DIR/plan.md`)
   - The builder's code, tests, and artifacts
   - NEVER pass the builder's self-assessment or reasoning

2. **Gate 3:** Check verification report.
   - **PASS** → Task is done. Use `TaskUpdate` to mark `completed`. Move to next.
   - **NEEDS ITERATION** → Keep task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": 1}` to track count. Enter iteration loop (Phase 4).
   - **FAIL** → Same as NEEDS ITERATION.

**After Gate 3 (all tasks in wave checked):** Summarize verification verdicts to the user: which tasks passed, which need iteration, key findings.

If all tasks PASS:
- If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to integration (Phase 5).
- Otherwise, use `AskUserQuestion` with options:
  - "Proceed to integration (Recommended)" — spawn Integrator for this wave
  - "Review verification reports" — let the user inspect reports before integration

If any tasks NEED ITERATION:
- If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to Phase 4 iteration on failing tasks.
- Otherwise, use `AskUserQuestion` with options:
  - "Iterate on failing tasks (Recommended)" — enter Phase 4 for failing tasks
  - "Re-plan failing tasks" — send back to Planner for re-decomposition
  - "Skip failing tasks and continue" — proceed with passing tasks only

## Phase 4: Iterate (if needed)

1. Extract the Verifier's feedback (not their internal reasoning).
2. Pass ONLY the feedback to the original Builder agent via `SendMessage`.
3. Builder revises and resubmits.
4. Verifier re-checks (same information barrier rules).
5. Max 3 iterations. If still failing, use `AskUserQuestion` to present options:
   - "Re-plan this task" — send back to Planner for re-decomposition
   - "Skip and continue (Recommended)" — mark task as skipped, proceed with remaining tasks
   - "Stop pipeline" — halt the pipeline for manual intervention

   Use `TaskUpdate` with `metadata: {"iteration": N}` to track each cycle.

Track iterations in `$RND_DIR/iteration-log.md`.

## Phase 5: Integrate

Once ALL tasks in a wave pass verification:

1. Spawn the `rnd-integrator` agent as a **teammate** with `team_name: "rnd-pipeline"`.
2. It merges outputs, runs integration tests, checks for regressions.
3. **Gate 4:** SHIP or NO-SHIP.

**After Gate 4:** Summarize integration results to the user.

If SHIP:
- If more waves remain:
  - If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to Phase 2 for the next wave.
  - Otherwise, use `AskUserQuestion` with options:
    - "Proceed to next wave (Recommended)" — start Phase 2 for the next wave
    - "Review integration report" — let the user inspect the report first
- If this was the last wave: "Pipeline complete." Use `AskUserQuestion` with options:
  - "Review all artifacts" — show the user a summary of everything produced
  - "Proceed to cleanup (Recommended)" — move to Phase 6

If NO-SHIP, use `AskUserQuestion` with options:
- "Fix failing integration points (Recommended)" — route back to relevant builders
- "Re-plan affected tasks" — send failing tasks back to the Planner

## Phase 6: Report & Cleanup

Summarize results for the user:
- What was built
- Verification results
- Any iterations that occurred
- Final integration status
- Remaining concerns or recommendations

Use `AskUserQuestion` to present concrete next steps:
- "Commit changes (Recommended)" — stage and commit all changes from the pipeline
- "Create PR" — commit and open a pull request
- "Review all artifacts" — show the user a summary of everything produced
- "Clean up" — remove `$RND_DIR` artifacts and team resources only

Use `TeamDelete` to clean up the `rnd-pipeline` team after the pipeline completes or is abandoned.
