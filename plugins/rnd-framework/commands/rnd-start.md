---
description: "Start the R&D orchestration framework for a complex task. Runs the full pipeline: Plan → Build → Verify → Integrate. Supports single-flow and multi-agent execution modes."
argument-hint: "<description of the feature, refactor, or bug fix>"
effort: high
---

# R&D Framework: Full Pipeline

You are orchestrating a complex coding task using the R&D framework — a scientific-method pipeline.

## Mode Selection

Before proceeding, determine the execution mode. Use `AskUserQuestion`/`AskUser` to present the choice:

- **"Single-flow mode (Recommended)"** — All phases run sequentially in this session. No agents are spawned. Best for most tasks; avoids rate-limit overhead.
- **"Multi-agent mode"** — Pipeline phases are executed by specialized agents spawned as subagents (`rnd-planner`, `rnd-builder`, `rnd-verifier`, `rnd-integrator`). Each agent has a dedicated model, skill preloading, and role. Best for complex multi-task pipelines requiring deep specialization and mechanically-enforced information barriers.

If the user has already specified a mode (e.g., "use multi-agent"), skip the prompt and proceed with their choice.

**Single-flow mode:** All phases below are executed directly by this session. Skills provide phase-specific discipline.

**Multi-agent mode:** The orchestrator (this session) spawns specialized agents for each phase. Use `subagent_type` to spawn agents (e.g., `subagent_type: "rnd-builder"`). Agents communicate results back via `SendMessage`. The orchestrator manages phase gates, collects artifacts, and coordinates the pipeline. See `rnd-framework:rnd-orchestration` for agent roles and coordination protocol.

## Setup

Determine the RND artifacts directory and create its structure:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

Use `$RND_DIR` for all artifact paths below.

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:rnd-start` with no task description):

1. **Quick codebase scan:** `git log --oneline -10`, TODO/FIXME comments, recent changes.
2. **Ask with `AskUserQuestion`/`AskUser`:** 2-4 concrete suggestions based on what you found, plus "Describe a different task".
3. Use the selected or typed task as the task description and proceed to Phase 0.

**Never fall back to plain text** — `AskUserQuestion`/`AskUser` is mandatory at every decision point.

If `$ARGUMENTS` is provided, skip this section and proceed directly.

## Phase 0: Discovery

Before planning, explore the codebase and gather requirements.

1. **Explore the codebase.** Use Glob/Grep to identify: existing patterns, relevant files/modules, architectural conventions, and constraints.

2. **Discover local experts.** Invoke `rnd-framework:rnd-local-experts` to scan `.claude/agents/` and `.claude/skills/` for project-local agents and skills. If none exist, record `Local Experts Discovered: none` and continue.

3. **Load coding practices.** Detect which languages/frameworks are present. Invoke `rnd-framework:kiss-practices` and `rnd-framework:fp-practices` in a single message (parallel).

4. **Check roadmap scope.** Run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --roadmap` to get the roadmap path. Check if the file exists.

   - **If `roadmap.md` exists:** Read it and display milestone progress. Use `AskUserQuestion`/`AskUser` with options:
     - "Start next milestone: [milestone title] (Recommended)" — use the milestone description as the task
     - "Start a different task" — continue with `$ARGUMENTS`, ignoring the roadmap
     - "Manage roadmap" — route to `/rnd-framework:rnd-roadmap`
   - **If `roadmap.md` does not exist:** If the task seems multi-day, `AskUserQuestion`/`AskUser`: "Create a roadmap first (Recommended)" or "Proceed as single session". If single-session, skip silently.

5. **Discover environment and infrastructure.** Run a structured checklist scan to catalog the project's build environment:
   - **Package manager:** Glob for package.json, Cargo.toml, mix.exs, go.mod, pyproject.toml
   - **Test framework:** Grep for test runner configs (vitest, jest, pytest, etc.), count existing tests, identify exact run commands
   - **CI config:** Read .github/workflows/ or equivalent — extract build/test/deploy commands
   - **External services:** Grep for https:// URLs in source to catalog APIs, databases, third-party services (note auth requirements)
   - **Environment variables:** Read .env.example or .env.template, Grep for process.env/ENV references
   - **Secrets and off-limits:** Infer from .gitignore, CI secrets config, and sensitive file paths

   Present findings to the user via `AskUserQuestion`/`AskUser` for confirmation and gap-filling. This feeds into the Environment Setup, Infrastructure, and Testing Strategy sections of plan.md.

6. **Identify ambiguities.** Note what is unclear: scope boundaries, architectural choices, integration points, edge cases, or user preferences.

7. **Ask 3-5 clarifying questions** using `AskUserQuestion`/`AskUser`. Focus on scope, patterns, constraints, and preferences. Provide 2-4 options per question based on what you found in the codebase.

8. **Compile discovery context.** Summarize: (a) codebase findings, (b) local experts, (c) KISS/FP rules, (d) environment/infrastructure findings, (e) user answers, (f) constraints.

**Skip condition:** If the task description is already highly specific (file paths, approach details, clear scope), skip Phase 0 and proceed to Phase 0.5.

## Phase 0.5: Design Exploration

Before committing to a plan, explore architectural alternatives. Invoke `rnd-framework:rnd-design` for the full protocol.

**Skip condition:** Skip if the task is highly specific or a small refactor with no meaningful architectural ambiguity.

If **auto-continue mode is ON**, automatically select the recommended approach and proceed to Phase 1 without pausing.

Otherwise:

1. **Generate 2-3 architectural alternatives** from Phase 0 context.
2. **Recommend one approach** with reasons tied to Phase 0 constraints.
3. **Save design spec** to `$RND_DIR/design-spec.md`. Status: `STATUS: DRAFT`.
4. **Present for approval** — `AskUserQuestion`/`AskUser`: "Approve design (Recommended)", "Approve with modifications", "Choose a different alternative", "Request another alternative", "Skip design phase".
5. **Iterate on feedback** (max 3 rounds). After 3 rounds without approval, report blocked.
6. **Finalize** — set `STATUS: APPROVED`.

## Phase 1: Plan

Invoke `rnd-framework:rnd-decomposition` to guide decomposition. Using that skill's protocol, decompose the task yourself:

1. Write structured exploration findings to `$RND_DIR/exploration/` (one markdown file per area explored).
2. Decompose the task into a hierarchical task tree with pre-registration documents.
3. Build the dependency matrix and execution schedule.
4. Save to `$RND_DIR/plan.md`.

**Gate 1:** Every criterion must be empirically verifiable — a skeptical Verifier must produce a true/false result from evidence alone. "Works correctly", "handles errors", "is performant" are automatic rejections. Revise until every criterion specifies an observable outcome.

**After Gate 1 passes:** Summarize the plan to the user. Use `AskUserQuestion`/`AskUser` with options:
- "Approve plan and auto-continue (Recommended)" — run the full pipeline automatically, pausing only for escalations
- "Approve plan and start building" — proceed with manual gates at each phase boundary
- "Request plan revisions"
- "Add more tasks"

If the user selects "Approve plan and auto-continue", set **auto-continue mode = ON**. This skips happy-path gates in Phases 2, 3, and 5. Escalation gates are always preserved.

Once approved, create a `TaskCreate` entry for each task.

## Phase 2: Build (per wave)

Invoke `rnd-framework:rnd-building` to load build discipline. For each wave in the execution schedule, build each task sequentially:

1. **Mark tasks as started:** `TaskUpdate` each task to `in_progress`.

2. **Inject learnings.** For each task, detect languages from file extensions in "Expected outputs". Read `$CLAUDE_CONFIG_DIR/learnings/{language}.md` and use as context. Skip silently if no file exists.

3. **Build each task sequentially.** For each task in the wave:
   - Read the pre-registration and exploration cache
   - Verify external dependencies against actual systems
   - Implement using TDD (Red-Green-Refactor per criterion)
   - Save build manifest to `$RND_DIR/builds/T<id>-manifest.md`
   - Save honest self-assessment to `$RND_DIR/builds/T<id>-self-assessment.md`
   - Assess your own status: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, or BLOCKED

4. **Route each result by status code:**

   | Status code | Action |
   |-------------|--------|
   | `DONE` | Proceed to Gate 2. |
   | `DONE_WITH_CONCERNS` | Proceed to Gate 2. Note concerns for verification phase. |
   | `NEEDS_CONTEXT` | Pause. `AskUserQuestion`/`AskUser` to get missing info. Resume with user's answer. |
   | `BLOCKED` | Pause. `AskUserQuestion`/`AskUser`: "Re-plan this task (Recommended)", "Provide a workaround", "Skip this task". |

5. **Gate 2:** Confirm code, tests, artifacts, and self-assessment. `TaskUpdate` each task to `completed`.

**After Gate 2:** Summarize results. If **auto-continue mode is ON**, proceed directly to Phase 2.5. Otherwise, `AskUserQuestion`/`AskUser`:
- "Proceed to verification (Recommended)"
- "Review build artifacts first"

## Phase 2.5: Reality Audit (blocking)

For each task with external dependencies, invoke `rnd-framework:rnd-reality-auditing` to adversarially test external service contracts. Save reports to `$RND_DIR/reality/`. Statuses: `VALIDATED_ALL`, `VALIDATED_PARTIAL`, `INVALID_FOUND`, `SKIPPED`. If `INVALID_FOUND`, route back to Phase 2 with the reality report as feedback before verification.

## Phase 3: Verify (per task)

**CRITICAL: Information Barrier.** Do NOT read `$RND_DIR/builds/T<id>-self-assessment.md` during verification. The `read-gate.sh` hook enforces this mechanically. You wrote the self-assessment during build, but during verification you must assess work purely against the pre-registered spec.

Invoke `rnd-framework:rnd-verification` to load verification discipline. For each completed task:

1. **Pre-flight:** Confirm `$RND_DIR/builds/T<id>-self-assessment.md` exists but do NOT read it. Assemble verification context from pre-registration and builder artifacts only. Read **Criticality** from the pre-registration (default: NORMAL if absent).

2. **Write independent experiment tests** — before reviewing your own build code, write one experiment test per criterion. Derive from spec text only. Save to `$RND_DIR/verifications/T<id>-experiments/`.

3. **Run experiments against the built code.** Record raw output verbatim.

4. **Run the built tests and compare.** Check test adequacy per criterion.

5. **Code inspection and failure mode analysis.** Scan for boundary cases, error handling, race conditions, external contract conformance. Cross-reference build manifest evidence.

6. **Produce verification report** at `$RND_DIR/verifications/T<id>-verification.md`.

7. **Gate 3:** Check the verdict:
   - **PASS** → `TaskUpdate` to `completed`. Move to next.
   - **PASS (quality: NEEDS ITERATION)** → `TaskUpdate` to `completed`. Save quality feedback. Does NOT block integration.
   - **NEEDS ITERATION** → Keep `in_progress`. Track with `metadata: {"iteration": N}`. Enter Phase 4.
   - **FAIL** → Do NOT iterate — route to re-planning.

**After Gate 3:** Summarize verdicts. Then route:

- All PASS/PASS(quality): auto-continue to Phase 5, or `AskUserQuestion`/`AskUser`: "Proceed to integration (Recommended)", "Iterate on quality first", "Review verification reports".
- Any NEEDS ITERATION: auto-continue to Phase 4, or `AskUserQuestion`/`AskUser`: "Iterate on failing tasks (Recommended)", "Skip failing tasks and continue".
- Any FAIL (always pauses): `AskUserQuestion`/`AskUser`: "Re-plan failing tasks (Recommended)", "Iterate anyway", "Skip failing tasks and continue".

## Phase 4: Iterate (if needed)

1. Extract feedback from the verification report (WHAT is wrong, not HOW to fix).
2. Re-invoke `rnd-framework:rnd-building`. Fix all failed criteria in a single pass.
3. Save updated manifest and self-assessment.
4. Re-invoke `rnd-framework:rnd-verification` to re-verify (same information barrier rules).
5. **If re-verification returns PASS**, extract a learning via `rnd-framework:rnd-learning`.
6. If iteration budget exhausted (LOW=2, NORMAL=3, HIGH=5), `AskUserQuestion`/`AskUser`:
   - "Re-plan this task"
   - "Skip and continue (Recommended)"
   - "Stop pipeline"

Track iterations in `$RND_DIR/iteration-log.md`.

### Skip Procedure

1. `TaskUpdate`: `status: "completed"`, `metadata: {"skipped": true, "reason": "..."}`.
2. Check downstream dependents via `TaskList`. Warn the user and `AskUserQuestion`/`AskUser` for each: skip dependent, proceed anyway, or re-plan.

## Phase 5: Integrate

Invoke `rnd-framework:rnd-integration` to load integration discipline. Perform integration yourself:

1. Confirm all tasks in the wave are verified (check `$RND_DIR/verifications/`).
2. Ensure all code integrates cleanly — no conflicts, interfaces match, imports correct.
3. Run integration tests and the project's existing test suite.
4. For the final wave, run full system validation.
5. Save integration report to `$RND_DIR/integration/wave-<N>-report.md`.
6. **Gate 4:** SHIP or NO-SHIP.

**After Gate 4:** Summarize results.

If SHIP and more waves remain: auto-continue to Phase 2 next wave, or `AskUserQuestion`/`AskUser`:
- "Proceed to next wave (Recommended)"
- "Review integration report"

If SHIP and last wave: `AskUserQuestion`/`AskUser`:
- "Review all artifacts"
- "Proceed to cleanup (Recommended)"

If NO-SHIP: `AskUserQuestion`/`AskUser`:
- "Fix failing integration points (Recommended)"
- "Re-plan affected tasks"

## Phase 6: Report & Cleanup

Summarize: what was built, verification results, iterations, integration status, remaining concerns.

**MANDATORY — DO NOT SKIP:** Invoke `rnd-framework:rnd-formatting` BEFORE doc-polish to run the project's formatter on pipeline-changed files.

**MANDATORY — DO NOT SKIP:** Invoke `rnd-framework:rnd-doc-polish` AFTER formatting but BEFORE presenting next steps.

Use `AskUserQuestion`/`AskUser` for next steps:
- "Commit changes (Recommended)"
- "Bump version, tag and push"
- "Run code review first"
- "Create PR"
- "Show development narrative"
- "Review all artifacts"
- "Finish session"

### Development Narrative

When the user selects "Show development narrative," generate a prose story of the pipeline run. If context was compressed, re-read `$RND_DIR/plan.md`, build manifests, verification reports, and `$RND_DIR/iteration-log.md` first. Cover: what was built and why, key decisions, obstacles and iterations, insights gained, and what's left. Write 3-5 paragraphs in first-person plural ("we"), not bullet points.

After showing the narrative, re-present the same `AskUserQuestion`/`AskUser` menu without the narrative option.
