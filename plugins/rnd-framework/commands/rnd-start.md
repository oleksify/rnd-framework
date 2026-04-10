---
description: "Start the R&D orchestration framework for a complex task. Runs the full pipeline: Plan → Build → Verify → Integrate using specialized agents."
argument-hint: "<description of the feature, refactor, or bug fix>"
effort: high
---

# R&D Framework: Full Pipeline

You are orchestrating a complex coding task using the R&D framework — a scientific-method pipeline.

The orchestrator (this session) spawns specialized agents for each phase. Use `subagent_type` to spawn agents (e.g., `subagent_type: "rnd-framework:rnd-builder"`). Agents communicate results back via `SendMessage`. The orchestrator manages phase gates, collects artifacts, and coordinates the pipeline. See `rnd-framework:rnd-orchestration` for agent roles and coordination protocol.

## Setup

Determine the RND artifacts directory and create its structure:

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

Use `$RND_DIR` for all artifact paths below.

## Task Input

If `$ARGUMENTS` is empty (user ran `/rnd-framework:rnd-start` with no task description):

1. **Quick codebase scan:** `git log --oneline -10`, TODO/FIXME comments, recent changes.
2. **Ask with `AskUserQuestion`:** 2-4 concrete suggestions based on what you found, plus "Describe a different task".
3. Use the selected or typed task as the task description and proceed to Phase 0.

**Never fall back to plain text** — `AskUserQuestion` is mandatory at every decision point.

If `$ARGUMENTS` is provided, skip this section and proceed directly.

## Phase 0: Discovery

Before planning, explore the codebase and gather requirements.

1. **Explore the codebase.** Use Glob/Grep to identify: existing patterns, relevant files/modules, architectural conventions, and constraints.

2. **Discover local experts.** Invoke `rnd-framework:rnd-local-experts` to scan `.claude/agents/` and `.claude/skills/` for project-local agents and skills. If none exist, record `Local Experts Discovered: none` and continue.

3. **Load coding practices.** Detect which languages/frameworks are present. Invoke `rnd-framework:kiss-practices` and `rnd-framework:fp-practices` in a single message (parallel).

4. **Check roadmap scope.** Run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --roadmap` to get the roadmap path. Check if the file exists.

   - **If `roadmap.md` exists:** Read it and display milestone progress. Use `AskUserQuestion` with options:
     - "Start next milestone: [milestone title] (Recommended)" — use the milestone description as the task
     - "Start a different task" — continue with `$ARGUMENTS`, ignoring the roadmap
     - "Manage roadmap" — route to `/rnd-framework:rnd-roadmap`
   - **If `roadmap.md` does not exist:** If the task seems multi-day, `AskUserQuestion`: "Create a roadmap first (Recommended)" or "Proceed as single session". If single-session, skip silently.

5. **Load project facts.** Check for a persistent project facts file:

   ```bash
   FACTS_PATH=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --facts)
   ```

   - **If `project-facts.md` exists:** Read it and compare its `Scan commit:` line against `git rev-parse HEAD`.
     - **If fresh** (commits match): Use the facts directly — they will populate plan.md's Environment Setup, Infrastructure, Worker Guidelines, and Testing Strategy sections during Phase 1. Skip the manual discovery checklist.
     - **If stale** (commits differ): Use `AskUserQuestion`: "Rescan project facts (Recommended)" — run `/rnd-framework:rnd-scan`, then continue; "Use existing facts" — proceed with stale facts; "Do manual discovery" — fall through to the checklist below.
   - **If `project-facts.md` does not exist:** Use `AskUserQuestion`: "Scan project now (Recommended)" — run `/rnd-framework:rnd-scan`, then continue; "Do manual discovery" — run the environment checklist below.

   **Manual discovery fallback** (only when project-facts.md is missing and user declines scan):
   - **Package manager:** Glob for package.json, Cargo.toml, mix.exs, go.mod, pyproject.toml
   - **Test framework:** Grep for test runner configs (vitest, jest, pytest, etc.), count existing tests, identify exact run commands
   - **CI config:** Read .github/workflows/ or equivalent — extract build/test/deploy commands
   - **External services:** Grep for https:// URLs in source to catalog APIs, databases, third-party services (note auth requirements)
   - **Environment variables:** Read .env.example or .env.template, Grep for process.env/ENV references
   - **Secrets and off-limits:** Infer from .gitignore, CI secrets config, and sensitive file paths

   Present findings to the user via `AskUserQuestion` for confirmation and gap-filling. This feeds into the Environment Setup, Infrastructure, and Testing Strategy sections of plan.md.

6. **Identify ambiguities.** Note what is unclear: scope boundaries, architectural choices, integration points, edge cases, or user preferences.

7. **Ask 3-5 clarifying questions** using `AskUserQuestion`. Focus on scope, patterns, constraints, and preferences. Provide 2-4 options per question based on what you found in the codebase.

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
4. **Present for approval** — `AskUserQuestion`: "Approve design (Recommended)", "Approve with modifications", "Choose a different alternative", "Request another alternative", "Skip design phase".
5. **Iterate on feedback** (max 3 rounds). After 3 rounds without approval, report blocked.
6. **Finalize** — set `STATUS: APPROVED`.

## Phase 1: Plan

**Spawn a Planner agent** to decompose the task:

```
Agent({
  subagent_type: "rnd-framework:rnd-planner",
  mode: "bypassPermissions",
  prompt: "Task: <task description>\nRND_DIR: <path>\nDiscovery context: <Phase 0 findings>"
})
```

The Planner writes `$RND_DIR/plan.md` with pre-registrations, dependency matrix, and execution schedule.

**Gate 1:** Read the returned `plan.md`. Every criterion must be empirically verifiable — a skeptical Verifier must produce a true/false result from evidence alone. "Works correctly", "handles errors", "is performant" are automatic rejections. If any criterion is vague, send the Planner back with specific feedback.

**After Gate 1 passes:** Summarize the plan to the user. Use `AskUserQuestion` with options:
- "Approve plan and auto-continue (Recommended)" — run the full pipeline automatically, pausing only for escalations
- "Approve plan and start building" — proceed with manual gates at each phase boundary
- "Request plan revisions"
- "Add more tasks"

If the user selects "Approve plan and auto-continue", set **auto-continue mode = ON**. This skips happy-path gates in Phases 2, 3, and 5. Escalation gates are always preserved.

Once approved, create a `TaskCreate` entry for each task.

## Phase 2: Build (per wave)

**Before each wave:** Scan `$RND_DIR/builds/` and `$RND_DIR/verifications/` to confirm which tasks are complete. Skip tasks that already have build manifests or verification reports.

**For each task in the wave, spawn a Builder agent:**

```
Agent({
  subagent_type: "rnd-framework:rnd-builder",
  mode: "bypassPermissions",
  prompt: "Task: T<id>\nRND_DIR: <path>\nPre-registration: <paste from plan.md>\nLearnings: <language-specific learnings if any>"
})
```

Do NOT build tasks yourself. The Builder agent handles implementation, TDD, manifest creation, and self-assessment. It returns a status code: DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, or BLOCKED.

**Route each result:**

| Status code | Action |
|-------------|--------|
| `DONE` | Proceed to Gate 2. |
| `DONE_WITH_CONCERNS` | Proceed to Gate 2. Note concerns for verification. |
| `NEEDS_CONTEXT` | `AskUserQuestion` to get missing info. Re-spawn Builder with the answer. |
| `BLOCKED` | `AskUserQuestion`: "Re-plan this task (Recommended)", "Provide a workaround", "Skip this task". |

**Gate 2:** Verify `$RND_DIR/builds/T<id>-manifest.md` exists and is non-empty (use Bash `test -s`). If missing, report via `AskUserQuestion`. `TaskUpdate` each passing task to `completed`.

**After Gate 2:** If **auto-continue mode is ON**, proceed directly to Phase 2.5. Otherwise, `AskUserQuestion`:
- "Proceed to verification (Recommended)"
- "Review build artifacts first"

## Phase 2.5: Reality Audit (blocking)

For each task with external dependencies, **spawn a Reality Auditor agent:**

```
Agent({
  subagent_type: "rnd-framework:rnd-reality-auditor",
  mode: "bypassPermissions",
  prompt: "Task: T<id>\nRND_DIR: <path>\nExternal dependencies: <from pre-registration>"
})
```

Statuses: `VALIDATED_ALL`, `VALIDATED_PARTIAL`, `INVALID_FOUND`, `SKIPPED`. If `INVALID_FOUND`, route back to Phase 2 with the reality report as feedback before verification.

## Phase 3: Verify (per task)

**CRITICAL: Information Barrier.** The Verifier runs in a separate context window and cannot see the Builder's reasoning. The `read-gate.sh` hook blocks reads of self-assessment files. Do NOT pass self-assessment content to the Verifier.

**For each built task, spawn a Verifier agent:**

```
Agent({
  subagent_type: "rnd-framework:rnd-verifier",
  mode: "bypassPermissions",
  prompt: "Task: T<id>\nRND_DIR: <path>\nPre-registration: <paste from plan.md>"
})
```

Do NOT verify tasks yourself. The Verifier agent independently writes experiment tests, runs them, inspects the code, and produces a verification report. It returns a verdict: PASS, PASS (quality: NEEDS ITERATION), NEEDS ITERATION, or FAIL.

**Gate 3:** Verify `$RND_DIR/verifications/T<id>-verification.md` exists and is non-empty. Read the verdict:
- **PASS** → `TaskUpdate` to `completed`.
- **PASS (quality: NEEDS ITERATION)** → Same as PASS. Save quality feedback. Does NOT block integration.
- **NEEDS ITERATION** → Keep `in_progress`. Track with `metadata: {"iteration": N}`. Enter Phase 4.
- **FAIL** → Do NOT iterate — route to re-planning.

**After Gate 3:** Summarize verdicts. Then route:

- All PASS/PASS(quality): auto-continue to Phase 5, or `AskUserQuestion`: "Proceed to integration (Recommended)", "Iterate on quality first", "Review verification reports".
- Any NEEDS ITERATION: auto-continue to Phase 4, or `AskUserQuestion`: "Iterate on failing tasks (Recommended)", "Skip failing tasks and continue".
- Any FAIL (always pauses): `AskUserQuestion`: "Re-plan failing tasks (Recommended)", "Iterate anyway", "Skip failing tasks and continue".

## Phase 4: Iterate (if needed)

1. Extract feedback from the verification report (WHAT is wrong, not HOW to fix).
2. **Re-spawn a Builder agent** with the feedback. Do NOT fix the code yourself.
3. After the Builder returns, **re-spawn a Verifier agent** to re-verify (same information barrier).
4. **If re-verification returns PASS**, extract a learning via `rnd-framework:rnd-learning`.
5. If iteration budget exhausted (LOW=2, NORMAL=3, HIGH=5), `AskUserQuestion`:
   - "Re-plan this task"
   - "Skip and continue (Recommended)"
   - "Stop pipeline"

Track iterations in `$RND_DIR/iteration-log.md`.

### Skip Procedure

1. `TaskUpdate`: `status: "completed"`, `metadata: {"skipped": true, "reason": "..."}`.
2. Check downstream dependents via `TaskList`. Warn the user and `AskUserQuestion` for each: skip dependent, proceed anyway, or re-plan.

## Phase 5: Integrate

**Spawn an Integrator agent:**

```
Agent({
  subagent_type: "rnd-framework:rnd-integrator",
  mode: "bypassPermissions",
  prompt: "Wave: <N>\nRND_DIR: <path>\nVerified tasks: <list of T<id>s>"
})
```

Do NOT integrate yourself. The Integrator merges verified outputs, runs integration tests, and produces `$RND_DIR/integration/wave-<N>-report.md`.

**Gate 4:** Verify `$RND_DIR/integration/wave-<N>-report.md` exists and is non-empty.

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

When the user selects "Show development narrative," generate a prose story of the pipeline run. If context was compressed, re-read `$RND_DIR/plan.md`, build manifests, verification reports, and `$RND_DIR/iteration-log.md` first. Cover: what was built and why, key decisions, obstacles and iterations, insights gained, and what's left. Write 3-5 paragraphs in first-person plural ("we"), not bullet points.

After showing the narrative, re-present the same `AskUserQuestion` menu without the narrative option.
