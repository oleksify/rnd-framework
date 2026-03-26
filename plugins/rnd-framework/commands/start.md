---
description: "Start the R&D orchestration framework for a complex task. Runs the full pipeline: Plan → Schedule → Build → Verify → Integrate."
argument-hint: "<description of the feature, refactor, or bug fix>"
effort: high
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

1. **Quick codebase scan:** `git log --oneline -10`, TODO/FIXME comments, recent changes.
2. **Ask with `AskUserQuestion`:** 2-4 concrete suggestions based on what you found, plus "Describe a different task".
3. Use the selected or typed task as the task description and proceed to Phase 0.

**Never fall back to plain text** — `AskUserQuestion` is mandatory at every decision point.

If `$ARGUMENTS` is provided, skip this section and proceed directly.

## Phase 0: Discovery

Before planning, explore the codebase and gather requirements. This phase prevents the Planner from decomposing a task based on incomplete understanding.

1. **Explore the codebase.** Spawn an `Explore` agent (or Glob/Grep for small codebases). Identify: existing patterns, relevant files/modules, architectural conventions, and constraints.

2. **Discover local experts.** Invoke `rnd-framework:rnd-local-experts` to scan `.claude/agents/` and `.claude/skills/` for project-local agents and skills. Pass the structured summary to the Planner so it can reference them in pre-registration documents. If none exist, record `Local Experts Discovered: none` and continue.

3. **Load coding practices.** Detect which languages/frameworks are present (by file extensions, config files, or dependency manifests). Invoke `rnd-framework:kiss-practices` and `rnd-framework:fp-practices` in a single message (parallel). Include both KISS and FP rules in the discovery context passed to the Planner and all downstream agents.

4. **Check roadmap scope.** Run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --roadmap` to get the roadmap path. Check if the file exists.

   - **If `roadmap.md` exists:** Read it and display milestone progress. Use `AskUserQuestion` with options:
     - "Start next milestone: [milestone title] (Recommended)" — use the milestone description as the task
     - "Start a different task" — continue with `$ARGUMENTS`, ignoring the roadmap
     - "Manage roadmap" — route to `/rnd-framework:roadmap`
   - **If `roadmap.md` does not exist:** If the task seems multi-day, `AskUserQuestion`: "Create a roadmap first (Recommended)" or "Proceed as single session". If single-session, skip silently.

5. **Identify ambiguities.** Note what is unclear: scope boundaries, architectural choices, integration points, edge cases, or user preferences.

6. **Ask 3-5 clarifying questions** using `AskUserQuestion`. Focus on scope, patterns, constraints, and preferences. Provide 2-4 options per question based on what you found in the codebase.

7. **Compile discovery context.** Summarize: (a) codebase findings, (b) local experts (name + description, or "none"), (c) KISS/FP rules, (d) user answers, (e) constraints. Pass this to the Planner.

**Skip condition:** If the task description is already highly specific (file paths, approach details, clear scope), skip Phase 0 and proceed to Phase 0.5.

## Phase 0.5: Design Exploration

Before committing to a plan, explore architectural alternatives. Invoke `rnd-framework:rnd-design` for the full protocol.

**Skip condition:** Skip if the task is highly specific (file paths, concrete approach, clear scope) or a small refactor with no meaningful architectural ambiguity.

If **auto-continue mode is ON**, automatically select the recommended approach and proceed to Phase 1 without pausing.

Otherwise:

1. **Generate 2-3 architectural alternatives** from Phase 0 context: how it works, strengths, weaknesses, effort, risk.
2. **Recommend one approach** with reasons tied to Phase 0 constraints, key assumptions, and what would change the recommendation.
3. **Save design spec** to `$RND_DIR/design-spec.md` (format from `rnd-framework:rnd-design`). Status: `STATUS: DRAFT`.
4. **Present for approval** — output full design summary as text, then `AskUserQuestion`: "Approve design (Recommended)", "Approve with modifications", "Choose a different alternative", "Request another alternative", "Skip design phase".
5. **Iterate on feedback** (max 3 rounds). Update spec and re-present. After 3 rounds without approval, report blocked.
6. **Finalize** — set `STATUS: APPROVED`, pass spec to Planner.

## Phase 1: Plan

Spawn `rnd-framework:rnd-planner` with: task description, Phase 0 discovery context, and Phase 0.5 design spec (if `STATUS: APPROVED`). Wait for `$RND_DIR/plan.md`: task tree, pre-registration documents, dependency matrix, execution schedule.

**Gate 1:** Every criterion must be empirically verifiable — a skeptical Verifier must produce a true/false result from evidence alone. "Works correctly", "handles errors", "is performant" are automatic rejections. Send back until every criterion specifies an observable outcome.

**After Gate 1 passes:** Summarize the plan to the user. Use `AskUserQuestion` with options:
- "Approve plan and auto-continue (Recommended)" — run the full pipeline automatically, pausing only for escalations
- "Approve plan and start building" — proceed with manual gates at each phase boundary
- "Request plan revisions"
- "Add more tasks"

If the user selects "Approve plan and auto-continue", set **auto-continue mode = ON**. This skips happy-path gates in Phases 2, 3, and 5. Escalation gates (budget exhaustion, NO-SHIP, final completion) are always preserved.

Once approved, create a `TaskCreate` entry for each task: `subject` = task name, `description` = pre-registration content, `activeForm` = present-continuous form. Use `addBlockedBy` to mirror the dependency matrix.

## Phase 2: Build (per wave)

For each wave in the execution schedule:

1. **Mark tasks as started:** `TaskUpdate` each task to `in_progress`.

2. **Inject learnings.** For each task, detect languages from file extensions in "Expected outputs". Read `$CLAUDE_CONFIG_DIR/learnings/{language}.md` and append a `### Known gotchas for {language}` section to the builder prompt. Skip silently if no file exists.

3. **Spawn builders in parallel:** One agent per task with `subagent_type: "rnd-framework:rnd-builder"`, `name: "builder-T{id}"`, `mode: "bypassPermissions"`. Use `run_in_background: true` for all but the last builder to maximize parallelism. Do NOT use `TeamCreate` — teams conflict with the global task list.

4. **Route each result by status code:**

   | Status code | Action |
   |-------------|--------|
   | `DONE` | Proceed to Gate 2. |
   | `DONE_WITH_CONCERNS` | Proceed to Gate 2. Pass concerns summary to Verifier prompt (from status message, NOT self-assessment). |
   | `NEEDS_CONTEXT` | Pause. `AskUserQuestion` to get missing info, restate requirement, or skip. Re-dispatch with user's answer. |
   | `BLOCKED` | Pause. `AskUserQuestion`: "Re-plan this task (Recommended)", "Provide a workaround and re-dispatch", "Skip this task". |

5. **Gate 2:** Confirm code, tests, artifacts, and self-assessment. `TaskUpdate` each task to `completed`.

**After Gate 2:** Summarize results. If **auto-continue mode is ON**, proceed directly to Phase 2.5. Otherwise, `AskUserQuestion`:
- "Proceed to verification (Recommended)"
- "Review build artifacts first"

## Phase 2.5: Proof Gate (advisory)

Check Lean: `lake --version 2>/dev/null || elan which lean 2>/dev/null`. If unavailable, log and skip to Phase 2.5b. Otherwise spawn one `rnd-proof-gate` agent per task (parallel) with pre-registration criteria and `$RND_DIR/builds/T<id>-manifest.md`. Log statuses; include proof reports in Phase 3 judge prompts. Auto-continues regardless of results.

## Phase 2.5b: Reality Audit (blocking)

Spawn one `rnd-reality-auditor` agent per task (parallel) with pre-registration criteria and `$RND_DIR/builds/T<id>-manifest.md`. Statuses: `VALIDATED_ALL` (all contracts verified), `VALIDATED_PARTIAL` (some unreachable), `INVALID_FOUND` (mismatch found), `SKIPPED` (no external interactions). `VALIDATED_ALL/PARTIAL/SKIPPED` → proceed to Phase 3. `INVALID_FOUND` → **BLOCK**: route to Phase 4 with `$RND_DIR/reality/T<id>-reality-report.md` as builder feedback. Include reality reports in Phase 3 judge prompts. No AskUserQuestion.

## Phase 3: Verify (per task)

For each completed task in the wave:

1. **Pre-flight:** Confirm `$RND_DIR/builds/T<id>-self-assessment.md` exists but do NOT read it. Assemble the judge prompt from pre-registration and builder artifacts. Include proof and reality report paths as additional evidence if they exist. Read **Criticality** from the pre-registration (default: NORMAL if absent).

2. **Route by criticality** (budget: LOW=2, NORMAL=3, HIGH=5):

   | Criticality | Protocol |
   |-------------|----------|
   | LOW or NORMAL (or omitted) | Spawn one `rnd-verifier` agent. Save returned report to `$RND_DIR/verifications/T<id>-verification.md`. |
   | HIGH | Invoke `rnd-framework:rnd-multi-judge`. Spawn 2 verifiers in parallel; save to `T<id>-judge-a.md` and `T<id>-judge-b.md`. Spawn tiebreaker if they disagree; save to `T<id>-tiebreaker.md`. Save aggregated report. |

3. **Gate 3:** Check the verdict:
   - **PASS** → `TaskUpdate` to `completed`. Move to next.
   - **PASS (quality: NEEDS ITERATION)** → `TaskUpdate` to `completed`. Save quality feedback to `$RND_DIR/verifications/T<id>-quality-feedback.md`. Does NOT block integration.
   - **NEEDS ITERATION** → Keep `in_progress`. Track with `metadata: {"iteration": N}`. Enter Phase 4.
   - **FAIL** → Do NOT iterate — route to re-planning.

**After Gate 3:** Summarize verdicts. Then route:

- All PASS/PASS(quality): auto-continue to Phase 5, or `AskUserQuestion`: "Proceed to integration (Recommended)", "Iterate on quality first", "Review verification reports".
- Any NEEDS ITERATION: auto-continue to Phase 4, or `AskUserQuestion`: "Iterate on failing tasks (Recommended)", "Skip failing tasks and continue".
- Any FAIL (always pauses): `AskUserQuestion`: "Re-plan failing tasks (Recommended)", "Iterate anyway", "Skip failing tasks and continue".

**Quality iteration round (after integration SHIP):** If any task has deferred quality feedback: auto-continue defers, or `AskUserQuestion`: "Iterate on quality now", "Defer quality iteration (Recommended)".

## Phase 4: Iterate (if needed)

1. Extract Verifier feedback (not internal reasoning).
2. Spawn a new Builder with `subagent_type: "rnd-framework:rnd-builder"`, `name: "iter-builder-T{id}"`, `mode: "bypassPermissions"`. Include original pre-registration plus Verifier feedback.
3. Builder implements fix and produces updated artifacts.
4. Verifier re-checks (same information barrier rules).
7. **If re-verification returns PASS**, extract a learning via `rnd-framework:rnd-learning`: gotcha (from Verifier feedback), fix (from Builder diff), language (from changed file extensions). Append to `$CLAUDE_CONFIG_DIR/learnings/{language}.md`.
8. If iteration budget exhausted, `AskUserQuestion`:
   - "Re-plan this task"
   - "Skip and continue (Recommended)"
   - "Stop pipeline"

Track iterations in `$RND_DIR/iteration-log.md`.

### Skip Procedure

1. `TaskUpdate`: `status: "completed"`, `metadata: {"skipped": true, "reason": "..."}`.
2. Check downstream dependents via `TaskList`. Warn the user and `AskUserQuestion` for each: skip dependent, proceed anyway, or re-plan.
3. Inform the Integrator which tasks were skipped so it can exclude them and note them in the integration report.

## Phase 5: Integrate

1. Spawn `rnd-framework:rnd-integrator`.
2. It merges outputs, runs integration tests, checks for regressions.
3. **Gate 4:** SHIP or NO-SHIP.

**After Gate 4:** Summarize results.

If SHIP and more waves remain: auto-continue to Phase 2 next wave, or `AskUserQuestion`:
- "Proceed to next wave (Recommended)"
- "Review integration report"

If SHIP and last wave: `AskUserQuestion`:
- "Review all artifacts"
- "Proceed to cleanup (Recommended)"

If NO-SHIP: `AskUserQuestion`:
- "Fix failing integration points (Recommended)"
- "Re-plan affected tasks"

## Phase 6: Report & Cleanup

Summarize: what was built, verification results, iterations, integration status, remaining concerns.

**MANDATORY — DO NOT SKIP:** Invoke `rnd-framework:rnd-formatting` BEFORE doc-polish to run the project's formatter on pipeline-changed files.

**MANDATORY — DO NOT SKIP:** Invoke `rnd-framework:rnd-doc-polish` AFTER formatting but BEFORE presenting next steps.

Use `AskUserQuestion` for next steps:
- "Commit changes (Recommended)"
- "Bump version, tag and push"
- "Run code review first"
- "Create PR"
- "Show development narrative"
- "Review all artifacts"
- "Finish session"

### Development Narrative

When the user selects "Show development narrative," generate a prose story of the pipeline run (do NOT spawn agents). If context was compressed, re-read `$RND_DIR/plan.md`, build manifests, verification reports, and `$RND_DIR/iteration-log.md` first. Cover: what was built and why, key decisions, obstacles and iterations, insights gained, and what's left. Write 3-5 paragraphs in first-person plural ("we"), not bullet points.

After showing the narrative, re-present the same `AskUserQuestion` menu without the narrative option.
