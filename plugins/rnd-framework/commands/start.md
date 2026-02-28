---
description: "Start the R&D orchestration framework for a complex task. Runs the full pipeline: Plan → Schedule → Build → Verify → Integrate."
argument-hint: "<description of the feature, refactor, or bug fix>"
---

# R&D Framework: Full Pipeline

You are orchestrating a complex coding task using the R&D framework. Follow the phases below in strict order. Use subagents for parallelizable work.

## Setup

Create the `.rnd/` directory structure if it doesn't exist:

```
.rnd/
  plan.md
  builds/
  verifications/
  integration/
  iteration-log.md
```

Use `TeamCreate` to create a team named `rnd-pipeline` with a description matching the task. This team coordinates all agents for the pipeline run.

## Phase 1: Plan

Spawn the `rnd-planner` agent with the task description: $ARGUMENTS

Wait for the planner to produce `.rnd/plan.md` with:
- Task tree
- Pre-registration documents (with testable success criteria)
- Dependency matrix
- Execution schedule (waves)

**Gate 1:** Review the plan. Every criterion must be empirically verifiable — a skeptical Verifier must be able to produce a true/false result from evidence alone. Criteria like "works correctly", "handles errors", or "is performant" are automatic rejections. Send back to planner until every criterion specifies an observable outcome.

**After Gate 1 passes:** Create a `TaskCreate` entry for each task in the plan. Set `subject` to the task name, `description` to the pre-registration content, and `activeForm` to the present-continuous form (e.g., "Building OAuth handler"). Use `addBlockedBy` on each task to mirror the dependency matrix from the plan — if T3 depends on T1, then T3's `addBlockedBy` should include T1's task ID.

## Phase 2: Build (per wave)

For each wave in the execution schedule:

1. **Mark tasks as started:** Use `TaskUpdate` to set each task in the wave to `in_progress`.

2. **Parallel tasks within a wave:** Spawn one `rnd-builder` subagent per task as a **teammate** using the `Agent` tool with `team_name: "rnd-pipeline"`. They can run in parallel since tasks within a wave have no cross-dependencies.

3. **Wait for all builders in the wave to complete.** Builders report completion via `SendMessage`.

4. **Gate 2:** Confirm each builder produced code, tests, artifacts, and self-assessment. On pass, use `TaskUpdate` to mark each task as `completed`.

## Phase 3: Verify (per task)

For each completed task in the wave:

1. Spawn an `rnd-verifier` subagent as a **teammate** with `team_name: "rnd-pipeline"`. Pass it ONLY:
   - The task's pre-registration document (from `.rnd/plan.md`)
   - The builder's code, tests, and artifacts
   - NEVER pass the builder's self-assessment or reasoning

2. **Gate 3:** Check verification report.
   - **PASS** → Task is done. Use `TaskUpdate` to mark `completed`. Move to next.
   - **NEEDS ITERATION** → Keep task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": 1}` to track count. Enter iteration loop (Phase 4).
   - **FAIL** → Same as NEEDS ITERATION.

## Phase 4: Iterate (if needed)

1. Extract the Verifier's feedback (not their internal reasoning).
2. Pass ONLY the feedback to the original Builder agent via `SendMessage`.
3. Builder revises and resubmits.
4. Verifier re-checks (same information barrier rules).
5. Max 3 iterations. If still failing, report to user for re-planning or manual intervention. Use `TaskUpdate` with `metadata: {"iteration": N}` to track each cycle.

Track iterations in `.rnd/iteration-log.md`.

## Phase 5: Integrate

Once ALL tasks in a wave pass verification:

1. Spawn the `rnd-integrator` agent as a **teammate** with `team_name: "rnd-pipeline"`.
2. It merges outputs, runs integration tests, checks for regressions.
3. **Gate 4:** SHIP or NO-SHIP.
   - **SHIP** → Proceed to next wave or finish.
   - **NO-SHIP** → Identify failing integration points, route back to relevant builders via `SendMessage`.

## Phase 6: Report & Cleanup

Summarize results for the user:
- What was built
- Verification results
- Any iterations that occurred
- Final integration status
- Remaining concerns or recommendations

Use `TeamDelete` to clean up the `rnd-pipeline` team after the pipeline completes or is abandoned.
