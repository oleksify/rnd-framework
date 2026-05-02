---
description: "Resume a partially-completed R&D pipeline from where it left off by scanning artifacts and reconstructing task state."
effort: medium
---

# R&D Framework: Resume

## Setup

Determine the RND artifacts directory for the current session:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")
```

## Step 1: Validate Active Session

If `$RND_DIR` is empty, does not exist, or does not contain `plan.md`, display:

> No active pipeline session found. Start a new pipeline with `/rnd-framework:rnd-start <task>`.

Then stop — do not proceed further.

## Step 2: Parse plan.md

Read `$RND_DIR/plan.md` and extract:

1. **Task IDs** — scan the Pre-Registration Documents section for lines matching the pattern `Task ID: T<number>`. Collect all task IDs found (e.g., T1, T2, T3).

2. **Wave assignments** — read the Execution Schedule section. Each subsection heading (`### Wave N: T1, T2`) lists which tasks belong to which wave. Record the wave number for each task ID.

3. **Dependency relationships** — read the Dependency Matrix section. For each task, record its "Depends On" column entries. These will be used to set `addBlockedBy` when recreating tasks.

4. **Task names** — from each Pre-Registration Document block, extract the task name from the `Intent:` line or the task title in the Task Tree section.

## Step 3: Scan Build Artifacts

Scan `$RND_DIR/builds/` for files matching the pattern `T*-manifest.md`. For each file found, extract the task ID from the filename (e.g., `T1-manifest.md` → task T1). These are the **built tasks**.

Do NOT read `T*-self-assessment.md` files. The information barrier applies here.

## Step 4: Scan Verification Artifacts

Scan `$RND_DIR/verifications/` for files matching the pattern `T*-verification.md`. For each file found:

1. Extract the task ID from the filename.
2. Read the file and locate the final consensus verdict line. Extract the verdict:
   - `PASS` — task passed all criteria
   - `PASS (quality: NEEDS ITERATION)` — correctness passed, quality feedback exists
   - `NEEDS_ITERATION` — correctness failure, task must be rebuilt
   - `FAIL` — unrecoverable failure, task needs re-planning

Record the verdict for each verified task.

## Step 5: Scan Integration Artifacts

Scan `$RND_DIR/integration/` for files matching the pattern `wave-*-report.md`. For each file found:

1. Extract the wave number from the filename (e.g., `wave-1-report.md` → Wave 1).
2. Read the file and check for the verdict:
   - If the file contains `NO-SHIP`: verdict is `NO-SHIP`
   - If the file contains `SHIP` (but not `NO-SHIP`): verdict is `SHIP`

Record which waves have been integrated and their SHIP/NO-SHIP verdicts.

## Step 6: Check Iteration Log

If `$RND_DIR/iteration-log.md` exists, read it and extract the iteration cycle count for each task. Record any tasks currently in an active iteration cycle (these are `in_progress` with iteration metadata).

## Step 7: Reconstruct Per-Task Status

Using the data gathered in Steps 2-6, assign a status to each task:

| Condition | Status |
|-----------|--------|
| Task found in plan.md only (no build artifact) | `planned` |
| Build manifest exists, no verification report | `built` |
| Verification verdict is PASS or PASS (quality: NEEDS ITERATION) | `verified` |
| Verification verdict is NEEDS_ITERATION, iteration log shows active cycle | `iterating` |
| Wave integration report shows SHIP | `integrated` |
| Verification verdict is FAIL | `failed` |

## Step 8: Recreate Task Entries

Recreate the pipeline's task tracking state to mirror the reconstructed status:

1. **Create tasks.** For each task found in `plan.md`, issue a `TaskCreate` with:
   - `subject`: the task name (e.g., "T1: Create resume command")
   - `description`: the task's pre-registration content from `plan.md`
   - `activeForm`: present-continuous task description (e.g., "Building resume command")

2. **Set dependencies.** For each task that has entries in the "Depends On" column of the Dependency Matrix, call `TaskUpdate` with `addBlockedBy` listing the dependent task IDs. This mirrors the original pipeline's dependency graph.

3. **Set statuses.** For each task, call `TaskUpdate` to set the appropriate status:
   - `planned` tasks: `status: "pending"`
   - `built` tasks: `status: "completed"`
   - `verified` tasks: `status: "completed"`
   - `iterating` tasks: `status: "in_progress"` with `metadata: {"iteration": <count from iteration-log>}`
   - `integrated` tasks: `status: "completed"`
   - `failed` tasks: `status: "in_progress"` (flagged for re-planning)

## Step 9: Determine Next Phase

Based on the reconstructed state, determine where the pipeline left off:

| State | Next Phase |
|-------|-----------|
| plan.md exists, no built tasks | Phase 2 (Build) — Wave 1 |
| Some tasks built, none verified | Phase 3 (Verify) — current wave |
| Some tasks verified with PASS, none integrated | Phase 5 (Integrate) — current wave |
| Some tasks with NEEDS_ITERATION verdict | Phase 4 (Iterate) — failing tasks |
| Some tasks with FAIL verdict | Re-plan — route to Planner |
| Some waves SHIP, more waves remain | Phase 2 (Build) — next wave |
| All waves SHIP | Pipeline complete |

**Current wave** is the lowest-numbered wave that has any tasks not yet reaching `integrated` status.

## Step 10: Present Status Summary and Next Actions

Display a summary table of reconstructed pipeline state:

```
Wave | Task ID | Name                    | Status        | Iterations
-----|---------|-------------------------|---------------|----------
  1  | T1      | [task name]             | [status]      | [count or —]
  2  | T2      | [task name]             | [status]      | [count or —]
```

Then use `AskUserQuestion` to present the appropriate next-action options based on the reconstructed state:

**If plan exists but no builds yet (resume at Phase 2):**
- "Start building Wave 1 (Recommended)" — run the build phase for the first wave
- "Review plan before building" — display plan.md contents

**If some tasks built but not verified (resume at Phase 3):**
- "Verify built tasks (Recommended)" — run the verification phase for built tasks
- "Review build artifacts first" — let the user inspect code before verification

**If some tasks verified but not integrated (resume at Phase 5):**
- "Integrate verified tasks (Recommended)" — run the integration phase for the current wave
- "Review verification reports first" — let the user inspect reports before integration

**If some tasks need iteration (resume at Phase 4):**
- "Continue iterating on failing tasks (Recommended)" — re-run the build phase with verification feedback
- "Re-plan failing tasks" — re-run the planning phase for failing tasks
- "Skip failing tasks and proceed" — proceed without the failing tasks

**If some waves integrated, more remain (resume at Phase 2 for next wave):**
- "Build next wave (Recommended)" — run the build phase for the next wave
- "Review integration report" — let the user inspect the previous wave's integration report

**If pipeline is complete:**
- "Review all artifacts" — display a summary of all produced artifacts
- "Finish session" — run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish` to clear the current session ID

Once the user selects an action, invoke the corresponding phase logic from `/rnd-framework:rnd-start` to continue the pipeline from that point.
