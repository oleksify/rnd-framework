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


## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:start` with no task description):

1. **Quick codebase scan.** Run a few fast commands to gather context: `git log --oneline -10`, check for TODO/FIXME comments, look at recent changes. This takes seconds and informs your suggestions.

2. **Ask with `AskUserQuestion`.** Present 2-4 concrete task suggestions based on what you found, plus always include a generic "Describe a different task" option. Example suggestions might be: recent TODO items, areas with recent churn, or common improvement patterns you spotted. Each option should have a short label and a description explaining what the task would involve.

3. **If the user picks a suggestion**, use it as the task description and continue to Phase 0. **If they type a custom task**, use that instead.

**Never fall back to plain text** to ask what to work on. `AskUserQuestion` is mandatory at every decision point, including this one.

If `$ARGUMENTS` is provided, skip this section and proceed directly.

## Phase 0: Discovery

Before planning, explore the codebase and gather requirements. This phase prevents the Planner from decomposing a task based on incomplete understanding.

1. **Explore the codebase.** Spawn an `Explore` agent (or use Glob/Grep directly for small codebases) to understand the areas relevant to the task. Identify: existing patterns, relevant files/modules, architectural conventions, and potential constraints.

2. **Discover local experts.** Check whether the target project ships its own agents or skills in `.claude/`. Use Glob to scan:
   - `.claude/agents/*.md` — project-local agents
   - `.claude/skills/*/SKILL.md` — project-local skills

   For each discovered file, read the YAML frontmatter and extract the `name` and `description` fields. Assemble a structured summary:

   ```
   Local Experts Discovered:

   Agents (.claude/agents/):
     - name: security-reviewer
       description: "Reviews auth and input validation changes for vulnerabilities"

   Skills (.claude/skills/):
     - name: project-testing
       description: "Use when writing tests — covers project-specific test helpers and CI patterns"
   ```

   If neither `.claude/agents/` nor `.claude/skills/` exists, or both are empty, record `Local Experts Discovered: none` and continue silently. Missing directories are not an error.

3. **Identify ambiguities.** Based on your exploration and the task description, note what is unclear or could go multiple ways: scope boundaries, architectural choices, integration points, edge cases, or user preferences.

4. **Ask 3-5 clarifying questions.** Use `AskUserQuestion` to ask targeted questions about the ambiguities you found. Focus on:
   - **Scope:** What's in and what's out? Any specific files, modules, or areas to focus on or avoid?
   - **Patterns:** Should this follow an existing pattern in the codebase, or introduce a new approach?
   - **Constraints:** Performance requirements, compatibility needs, or dependencies to be aware of?
   - **Preferences:** Any strong opinions on architecture, naming, or approach?

   Keep questions concrete — provide 2-4 options per question based on what you discovered in the codebase, not generic open-ended asks.

5. **Compile discovery context.** Summarize: (a) relevant codebase findings, (b) local experts discovered (name + description for each, or "none"), (c) user answers, (d) any constraints discovered. This context is passed to the Planner.

**Skip condition:** If the task description is already highly specific (includes file paths, approach details, and clear scope), you may skip Phase 0 and proceed directly to Phase 1. When in doubt, ask — a few questions now prevents re-planning later.

## Phase 1: Plan

Before spawning the planner, create the planning-phase marker to block project file writes:
```bash
touch "$RND_DIR/.planning-phase"
```

Spawn an agent using the Agent tool with `subagent_type: "rnd-framework:rnd-planner"` and `mode: "bypassPermissions"`, passing the task description ($ARGUMENTS) **plus the discovery context from Phase 0** (codebase findings, local experts discovered, user answers, constraints). This gives the Planner pre-gathered context to inform decomposition — including any project-local agents or skills it may reference in pre-registration documents.

After the planner finishes — **whether successfully or with an error** — remove the marker:
```bash
rm -f "$RND_DIR/.planning-phase"
```

This cleanup is unconditional. If the planner agent errors out or is interrupted, the marker must still be removed so subsequent phases are not blocked from writing project files.

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

2. **Parallel tasks within a wave:** Spawn one agent per task using the Agent tool with `subagent_type: "rnd-framework:rnd-builder"` and `mode: "bypassPermissions"`. They can run in parallel since tasks within a wave have no cross-dependencies.

3. **Wait for all builders in the wave to complete.** The Agent tool is blocking — results return when the agent completes.

4. **Gate 2:** Confirm each builder produced code, tests, artifacts, and self-assessment. On pass, use `TaskUpdate` to mark each task as `completed`.

**After Gate 2:** Summarize build results to the user: which tasks completed, any deviations from plan, any escalations.

If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to verification (Phase 3).

Otherwise, use `AskUserQuestion` with options:
- "Proceed to verification (Recommended)" — spawn Verifiers for this wave
- "Review build artifacts first" — let the user inspect code before verification

## Phase 3: Verify (per task)

This phase uses multi-judge consensus verification. Invoke `rnd-framework:rnd-multi-judge` for the full protocol. Summary below.

For each completed task in the wave:

1. **Pre-flight:** Confirm `$RND_DIR/builds/T<id>-self-assessment.md` exists (build is complete) but do NOT read it. Assemble the shared judge prompt from the task's pre-registration document (from `$RND_DIR/plan.md`) and the builder's code, tests, and artifacts. NEVER include self-assessment content in any judge prompt.

2. **Spawn 2 independent judges in parallel** — both using the Agent tool with `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "bypassPermissions"`. Each judge receives the same prompt (pre-registration + builder code/tests). Neither judge's prompt includes the other judge's report. Both judges are blocked from reading self-assessment files (enforced by the `read-gate` hook). After each judge returns its report as text output, the orchestrator saves the returned report to:
   - Judge A: `$RND_DIR/verifications/T<id>-judge-a.md`
   - Judge B: `$RND_DIR/verifications/T<id>-judge-b.md`

3. **Consensus logic:** Read both reports and compare their `Overall Verdict` lines.
   - **Both judges agree** → their shared verdict is the final verdict. Proceed to step 5.
   - **Judges disagree** → proceed to step 4 (tiebreaker).

4. **Tiebreaker (on disagreement only):** Spawn a third verifier agent with `subagent_type: "rnd-framework:rnd-verifier"` and `mode: "bypassPermissions"`. Pass it: the pre-registration document, the builder's code and tests, AND both prior judge reports (Judge A and Judge B). Do NOT pass self-assessment files — the information barrier applies to the tiebreaker identically to the initial judges. After the tiebreaker returns its report as text output, the orchestrator saves the returned report to `$RND_DIR/verifications/T<id>-tiebreaker.md`. The tiebreaker's verdict is the final verdict.

5. **Save aggregated report** to `$RND_DIR/verifications/T<id>-verification.md` containing: Judge A report, Judge B report, tiebreaker report (if used), and the final consensus verdict with consensus method noted.

6. **Gate 3:** Check the consensus verdict (not individual judge verdicts).
   - **PASS** → Task is done. Use `TaskUpdate` to mark `completed`. Move to next.
   - **NEEDS ITERATION** → A clear, isolated failure the Builder can fix. Keep task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": 1}` to track count. Enter iteration loop (Phase 4).
   - **FAIL** → Multiple unmet criteria or no clear fix path. Do NOT iterate — route to re-planning.

**After Gate 3 (all tasks in wave checked):** Summarize verification verdicts to the user: which tasks passed, which need iteration, which failed outright.

If all tasks PASS:
- If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to integration (Phase 5).
- Otherwise, use `AskUserQuestion` with options:
  - "Proceed to integration (Recommended)" — spawn Integrator for this wave
  - "Review verification reports" — let the user inspect reports before integration

If any tasks got NEEDS ITERATION (but none FAIL):
- If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to Phase 4 iteration on failing tasks.
- Otherwise, use `AskUserQuestion` with options:
  - "Iterate on failing tasks (Recommended)" — enter Phase 4 for failing tasks
  - "Skip failing tasks and continue" — skip and proceed with passing tasks only (see skip procedure below)

If any tasks got FAIL:
- Use `AskUserQuestion` with options (even in auto-continue mode — FAIL always pauses):
  - "Re-plan failing tasks (Recommended)" — send back to Planner for re-decomposition
  - "Iterate anyway" — treat as NEEDS ITERATION (override Verifier's severity)
  - "Skip failing tasks and continue" — skip and proceed (see skip procedure below)

## Phase 4: Iterate (if needed)

1. Extract the Verifier's feedback (not their internal reasoning).
2. Spawn a new Builder agent using the Agent tool with `subagent_type: "rnd-framework:rnd-builder"` and `mode: "bypassPermissions"`, passing the original task pre-registration document PLUS the Verifier's feedback in the prompt.
3. The new Builder implements the fix and produces updated code, tests, and artifacts.
4. Verifier re-checks (same information barrier rules).
5. Max 3 iterations. If still failing, use `AskUserQuestion` to present options:
   - "Re-plan this task" — send back to Planner for re-decomposition
   - "Skip and continue (Recommended)" — skip this task and proceed (see skip procedure below)
   - "Stop pipeline" — halt the pipeline for manual intervention

   Use `TaskUpdate` with `metadata: {"iteration": N}` to track each cycle.

Track iterations in `$RND_DIR/iteration-log.md`.

### Skip Procedure

When the user chooses to skip a failing task:

1. Mark the task: `TaskUpdate` with `status: "completed"` and `metadata: {"skipped": true, "reason": "<why it was skipped>"}`.
2. **Check downstream dependencies.** Use `TaskList` to find any tasks that had this task in their `blockedBy`. For each dependent task:
   - Warn the user: "Task T{X} depends on skipped task T{Y}. It may fail or produce incomplete results."
   - Use `AskUserQuestion` to ask whether to also skip the dependent task, proceed anyway, or re-plan.
3. Inform the Integrator: when spawning the integrator for this wave, explicitly list which tasks were skipped so it can exclude them from merge and note them in the integration report.

## Phase 5: Integrate

Once all non-skipped tasks in a wave pass verification:

1. Spawn an agent using the Agent tool with `subagent_type: "rnd-framework:rnd-integrator"` and `mode: "bypassPermissions"`.
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
- "Clean up" — remove `$RND_DIR` artifacts only
- "Finish session" — run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish` to clear the current session ID; artifacts are preserved on disk, but the next pipeline run will start a fresh session
