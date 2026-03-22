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

3. **Load coding practices.** Detect which languages/frameworks are present in the project (by file extensions, config files, or dependency manifests). Invoke `rnd-framework:kiss-practices` and read only the relevant language files. Also invoke `rnd-framework:fp-practices` to load functional programming principles. Invoke both skills in a single message (parallel tool calls) to minimize API round-trips. Include both KISS and FP rules in the discovery context passed to the Planner and all downstream agents.

4. **Extract project coding standards.** Invoke `rnd-framework:rnd-standards` to scan the project's CLAUDE.md files, extract machine-checkable coding rules, and generate `$RND_DIR/project-patterns.json`. These patterns extend the slop gate's built-in catalog with project-specific enforcement rules that apply to all downstream Builders.

> **Note:** Quick mode (`/rnd-framework:quick`) skips these skill invocations and applies KISS/FP principles inline to reduce API call overhead.

5. **Check roadmap scope.** Run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --roadmap` to get the roadmap path. Check if the file exists.

   - **If `roadmap.md` exists:** Read it and display milestone progress (DONE / IN_PROGRESS / NOT_STARTED). Identify the current or next milestone. Use `AskUserQuestion` with options:
     - "Start next milestone: [milestone title] (Recommended)" — use the milestone description as the task, proceed to Phase 0.5/1
     - "Start a different task" — continue with the original `$ARGUMENTS`, ignoring the roadmap
     - "Manage roadmap" — route to `/rnd-framework:roadmap`
   - **If `roadmap.md` does not exist:** Based on your codebase exploration, evaluate whether the task seems like a multi-day effort (many components, broad scope, multiple subsystems). If multi-day, use `AskUserQuestion` with options:
     - "Create a roadmap first (Recommended)" — route to `/rnd-framework:roadmap` with the task description
     - "Proceed as single session" — continue normal pipeline

     If it seems single-session, skip silently.

6. **Identify ambiguities.** Based on your exploration and the task description, note what is unclear or could go multiple ways: scope boundaries, architectural choices, integration points, edge cases, or user preferences.

7. **Ask 3-5 clarifying questions.** Use `AskUserQuestion` to ask targeted questions about the ambiguities you found. Focus on:
   - **Scope:** What's in and what's out? Any specific files, modules, or areas to focus on or avoid?
   - **Patterns:** Should this follow an existing pattern in the codebase, or introduce a new approach?
   - **Constraints:** Performance requirements, compatibility needs, or dependencies to be aware of?
   - **Preferences:** Any strong opinions on architecture, naming, or approach?

   Keep questions concrete — provide 2-4 options per question based on what you discovered in the codebase, not generic open-ended asks.

8. **Compile discovery context.** Summarize: (a) relevant codebase findings, (b) local experts discovered (name + description for each, or "none"), (c) KISS rules for the project's tech stack, (d) user answers, (e) any constraints discovered. This context is passed to the Planner.

**Skip condition:** If the task description is already highly specific (includes file paths, approach details, and clear scope), you may skip Phase 0 and proceed directly to Phase 0.5. When in doubt, ask — a few questions now prevents re-planning later.

## Phase 0.5: Design Exploration

Before committing to a plan, explore architectural alternatives so the user can make an informed decision. Invoke `rnd-framework:rnd-design` for the full protocol. Summary below.

**Skip condition:** If the task description is already highly specific (includes file paths, a concrete implementation approach, and clear scope), skip this phase and proceed directly to Phase 1. Also skip if the task is a small refactor with no meaningful architectural ambiguity.

If **auto-continue mode is ON**, skip the approval gate — automatically select the recommended approach from the design spec and proceed to Phase 1 without pausing for user input.

Otherwise:

1. **Generate 2-3 architectural alternatives.** Using the discovery context from Phase 0 (codebase findings, user answers, constraints), identify meaningfully different approaches. For each alternative cover: how it works, strengths, weaknesses, effort estimate, and risk level.

2. **Recommend one approach.** State the recommended alternative with specific reasons tied to the constraints you found in Phase 0, the key assumptions that must hold, and what conditions would change the recommendation.

3. **Save design spec.** Write the spec to `$RND_DIR/design-spec.md` using the format defined in `rnd-framework:rnd-design`. Initial status is `STATUS: DRAFT`.

4. **Present for approval.** Output the full design summary as regular text first — include the alternatives comparison table, the full recommendation with all reasoning, key assumptions, and trade-offs. Do NOT abbreviate. Then use `AskUserQuestion` with short option labels (keep descriptions to one sentence — do NOT put the recommendation text in option descriptions):
   - "Approve design (Recommended)" — accept the recommended approach and proceed to Phase 1
   - "Approve with modifications" — apply requested changes, re-save, re-present (counts as one iteration)
   - "Choose a different alternative" — switch to a different listed approach, re-save, re-present
   - "Request another alternative" — generate a new option, re-save, re-present
   - "Skip design phase" — proceed to Phase 1 without a design spec (orchestrator decides approach)

5. **Iterate on feedback** (maximum 3 rounds). If the user requests changes, update `$RND_DIR/design-spec.md`, increment the iteration counter, and re-present via `AskUserQuestion`. After 3 rounds without approval, stop and report:

   ```
   BLOCKED on design approval after 3 iterations. User feedback: [summary].
   Awaiting guidance on how to proceed.
   ```

6. **Finalize.** Once approved (or auto-approved in auto-continue mode), update `$RND_DIR/design-spec.md` with `STATUS: APPROVED` and the approved approach name. This spec is passed to the Planner in Phase 1 alongside the discovery context.

## Phase 1: Plan

Spawn an agent using the Agent tool with `subagent_type: "rnd-framework:rnd-planner"`, passing the task description ($ARGUMENTS) **plus the discovery context from Phase 0** (codebase findings, local experts discovered, user answers, constraints) **and the approved design spec from Phase 0.5** (`$RND_DIR/design-spec.md` content, if it exists and has `STATUS: APPROVED`). This gives the Planner pre-gathered context to inform decomposition — including architectural decisions already made, rejected alternatives, and any project-local agents or skills it may reference in pre-registration documents.

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

2. **Inject learnings into builder prompts.** For each task in the wave, detect languages from the file extensions listed in the task's "Expected outputs" field (use the extension-to-language mapping from `rnd-framework:rnd-learning`). For each detected language, attempt to read `$CLAUDE_CONFIG_DIR/learnings/{language}.md`. If the file exists, append a `### Known gotchas for {language}` section to that task's builder prompt. If no learnings file exists for a language, skip silently — do not error or warn.

3. **Parallel tasks within a wave:** Spawn one agent per task using the Agent tool with `subagent_type: "rnd-framework:rnd-builder"`. They can run in parallel since tasks within a wave have no cross-dependencies.

4. **Wait for all builders in the wave to complete.** The Agent tool is blocking — results return when the agent completes.

5. **Route each builder result by status code.** For each completed builder, read the status code from its completion message and route accordingly:

   | Status code | Action |
   |-------------|--------|
   | `DONE` | Proceed to Gate 2 normally. |
   | `DONE_WITH_CONCERNS` | Proceed to Gate 2. Extract the concerns summary from the builder's status message (NOT from the self-assessment). Pass the concerns summary to the Verifier prompt for that task so the Verifier scrutinizes the flagged areas. |
   | `NEEDS_CONTEXT` | Pause this task. Use `AskUserQuestion` to present the builder's stated context gap and ask the user to provide the missing information, restate the requirement, or skip the task. Re-dispatch the builder with the user's answer appended to the original prompt. Do not advance to Gate 2 until the builder returns `DONE` or `DONE_WITH_CONCERNS`. |
   | `BLOCKED` | Pause this task. Use `AskUserQuestion` to present the blocker description and offer escalation options: "Re-plan this task (Recommended)", "Provide a workaround and re-dispatch", "Skip this task". Apply the chosen action before advancing to Gate 2. |

6. **Gate 2:** Confirm each builder produced code, tests, artifacts, and self-assessment. On pass, use `TaskUpdate` to mark each task as `completed`.

**After Gate 2:** Summarize build results to the user: which tasks completed, any deviations from plan, any escalations.

If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to Phase 2.5 (Proof Gate).

Otherwise, use `AskUserQuestion` with options:
- "Proceed to verification (Recommended)" — continue to Phase 2.5 (Proof Gate), then Phase 3
- "Review build artifacts first" — let the user inspect code before verification

## Phase 2.5: Proof Gate (advisory)

After all builders complete and pass Gate 2, attempt formal proofs if Lean is available.

1. **Check Lean availability.** Run `lake --version 2>/dev/null || elan which lean 2>/dev/null`. If both fail, log "Lean not available — skipping Proof Gate" and proceed directly to Phase 3. No user interaction needed. (`lake` is the reliable check when elan is installed via Homebrew; `elan which lean` resolves the real binary regardless of PATH shadowing.)

2. **Spawn proof-gate agents.** For each completed task in the wave, spawn one agent using the Agent tool with `subagent_type: "rnd-framework:rnd-proof-gate"`. Spawn all agents in a single message (parallel). Each agent prompt must include: the task's pre-registration criteria (from `$RND_DIR/plan.md`) and the path to builder output (`$RND_DIR/builds/T<id>-manifest.md`).

3. **Collect results.** Each agent returns a status (PROVEN_ALL, PROVEN_PARTIAL, NONE_PROVEN, SKIPPED). Log the statuses to the phase summary.

4. **Pass to Verifier.** Proof report paths are available at `$RND_DIR/proofs/T<id>-proof-report.md`. Include them in Phase 3 judge prompts when they exist (see Phase 3 step 1).

No AskUserQuestion — Proof Gate is advisory and auto-continues regardless of proof results.

## Phase 3: Verify (per task)

This phase uses multi-judge consensus verification. Invoke `rnd-framework:rnd-multi-judge` for the full protocol. Summary below.

For each completed task in the wave:

1. **Pre-flight:** Confirm `$RND_DIR/builds/T<id>-self-assessment.md` exists (build is complete) but do NOT read it. Assemble the shared judge prompt from the task's pre-registration document (from `$RND_DIR/plan.md`) and the builder's code, tests, and artifacts. NEVER include self-assessment content in any judge prompt. If `$RND_DIR/proofs/T<id>-proof-report.md` exists (Lean was available and Phase 2.5 ran), include its path in the judge prompt as additional evidence under "Additional evidence from Proof Gate".

2. **Spawn 2 independent judges in parallel** — both using the Agent tool with `subagent_type: "rnd-framework:rnd-verifier"`. Each judge receives the same prompt (pre-registration + builder code/tests, plus proof report if present). Neither judge's prompt includes the other judge's report. Both judges are blocked from reading self-assessment files (enforced by the `read-gate` hook). After each judge returns its report as text output, the orchestrator saves the returned report to:
   - Judge A: `$RND_DIR/verifications/T<id>-judge-a.md`
   - Judge B: `$RND_DIR/verifications/T<id>-judge-b.md`

3. **Consensus logic:** Read both reports and compare their `Overall Verdict` lines.
   - **Both judges agree** → their shared verdict is the final verdict. Proceed to step 5.
   - **Judges disagree** → proceed to step 4 (tiebreaker).

4. **Tiebreaker (on disagreement only):** Spawn a third verifier agent with `subagent_type: "rnd-framework:rnd-verifier"`. Pass it: the pre-registration document, the builder's code and tests, AND both prior judge reports (Judge A and Judge B). Do NOT pass self-assessment files — the information barrier applies to the tiebreaker identically to the initial judges. After the tiebreaker returns its report as text output, the orchestrator saves the returned report to `$RND_DIR/verifications/T<id>-tiebreaker.md`. The tiebreaker's verdict is the final verdict.

5. **Save aggregated report** to `$RND_DIR/verifications/T<id>-verification.md` containing: Judge A report, Judge B report, tiebreaker report (if used), and the final consensus verdict with consensus method noted.

6. **Gate 3:** Check the consensus verdict (not individual judge verdicts).
   - **PASS** → All criteria (both tiers) passed. Use `TaskUpdate` to mark `completed`. Move to next.
   - **PASS (quality: NEEDS ITERATION)** → Correctness is fully met; quality tier has feedback. Use `TaskUpdate` to mark `completed`. Record the quality feedback in `$RND_DIR/verifications/T<id>-quality-feedback.md` for a non-blocking iteration round after integration. Quality-tier failures do NOT block integration — proceed with the task marked completed.
   - **NEEDS ITERATION** → A clear, isolated Correctness failure the Builder can fix. Keep task `in_progress`. Use `TaskUpdate` with `metadata: {"iteration": 1}` to track count. Enter iteration loop (Phase 4).
   - **FAIL** → Multiple unmet Correctness criteria or no clear fix path. Do NOT iterate — route to re-planning.

**After Gate 3 (all tasks in wave checked):** Summarize verification verdicts to the user: which tasks passed fully, which passed with quality feedback (quality: NEEDS ITERATION), which need Correctness iteration, which failed outright.

If all tasks PASS or PASS (quality: NEEDS ITERATION) (no Correctness failures):
- If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to integration (Phase 5). Any quality feedback is deferred to the post-integration quality round.
- Otherwise, use `AskUserQuestion` with options:
  - "Proceed to integration (Recommended)" — spawn Integrator; quality-tier feedback deferred to post-integration
  - "Iterate on quality first" — address quality-tier feedback before integration (only if any task has `quality: NEEDS ITERATION`)
  - "Review verification reports" — let the user inspect reports before integration

If any tasks got NEEDS ITERATION (Correctness failure, but none FAIL):
- If **auto-continue mode is ON**, skip the following `AskUserQuestion` and proceed directly to Phase 4 iteration on failing tasks.
- Otherwise, use `AskUserQuestion` with options:
  - "Iterate on failing tasks (Recommended)" — enter Phase 4 for failing tasks
  - "Skip failing tasks and continue" — skip and proceed with passing tasks only (see skip procedure below)

If any tasks got FAIL:
- Use `AskUserQuestion` with options (even in auto-continue mode — FAIL always pauses):
  - "Re-plan failing tasks (Recommended)" — send back to Planner for re-decomposition
  - "Iterate anyway" — treat as NEEDS ITERATION (override Verifier's severity)
  - "Skip failing tasks and continue" — skip and proceed (see skip procedure below)

**Quality iteration round (after integration SHIP):** After integration succeeds, if any task recorded `quality: NEEDS ITERATION` feedback in `$RND_DIR/verifications/T<id>-quality-feedback.md`:
- If **auto-continue mode is ON**, defer quality iteration automatically — note the deferred quality feedback in the phase summary and skip the round.
- Otherwise, use `AskUserQuestion` with options:
  - "Iterate on quality now" — spawn Builder(s) with quality feedback from the recorded feedback files; re-verify and re-integrate if needed
  - "Defer quality iteration (Recommended)" — note the feedback in the report and skip; address separately in a future pipeline run

## Phase 4: Iterate (if needed)

1. Extract the Verifier's feedback (not their internal reasoning).
2. Spawn a new Builder agent using the Agent tool with `subagent_type: "rnd-framework:rnd-builder"`, passing the original task pre-registration document PLUS the Verifier's feedback in the prompt.
3. The new Builder implements the fix and produces updated code, tests, and artifacts.
4. Verifier re-checks (same information barrier rules).
5. **If re-verification returns PASS**, extract a learning from the cycle (invoke `rnd-framework:rnd-learning` for format and filing rules):
   - **Gotcha:** what failed — from the Verifier's NEEDS_ITERATION feedback
   - **Fix:** what changed — from the Builder's iteration diff
   - **Language:** determined from file extensions of changed files, using the extension-to-language mapping in `rnd-learning`
   - Append to `$CLAUDE_CONFIG_DIR/learnings/{language}.md` as `## Topic` + 1-3 terse bullets
   - If the language file is new, create it with a `# {Language} Learnings` heading and add a link in `$CLAUDE_CONFIG_DIR/learnings/INDEX.md`
6. Max 3 iterations. If still failing, use `AskUserQuestion` to present options:
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

1. Spawn an agent using the Agent tool with `subagent_type: "rnd-framework:rnd-integrator"`.
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

**MANDATORY — DO NOT SKIP:** You MUST invoke `rnd-framework:rnd-formatting` BEFORE doc-polish. This detects the project's formatter (biome, prettier, mix format, cargo fmt, etc.) and runs it on files changed by the pipeline. Report what was formatted (or that no formatter was detected). If you skip this step, pipeline-written code may not match the project's style.

**MANDATORY — DO NOT SKIP:** You MUST invoke `rnd-framework:rnd-doc-polish` AFTER formatting but BEFORE presenting the commit options below. This checks and updates CLAUDE.md, README.md, project docs, and stale inline comments. Report what was updated (or that everything is current). If you skip this step, the pipeline is incomplete.

Use `AskUserQuestion` to present concrete next steps:
- "Commit changes (Recommended)" — stage and commit all changes from the pipeline
- "Bump version, tag and push" — run `/rnd-framework:bump` to add a CHANGELOG entry, increment the patch version, commit, tag, and push. Use this when the pipeline produced a releasable change to a versioned project (e.g., a plugin, library, or package).
- "Run code review first" — run `/rnd-framework:review` on the changes before committing, to catch issues the pipeline may have missed
- "Create PR" — commit and open a pull request
- "Show development narrative" — generate a narrative explanation of the pipeline run (see below)
- "Review all artifacts" — show the user a summary of everything produced
- "Finish session" — run `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish` to clear the current session ID; artifacts are preserved on disk, but the next pipeline run will start a fresh session

### Development Narrative

When the user selects "Show development narrative," produce a human-readable story of the pipeline run. Do NOT spawn agents — generate this yourself from your pipeline context. If your conversation context has been compressed (long runs), re-read `$RND_DIR/plan.md`, `$RND_DIR/builds/T*-manifest.md`, `$RND_DIR/verifications/T*-verification.md`, and `$RND_DIR/iteration-log.md` to refresh your memory before writing. Cover:

1. **What was built and why** — the original request, how it evolved through discovery/design, what the final deliverables are
2. **Key decisions** — architectural choices made during design exploration, scope decisions during planning, trade-offs chosen and their rationale
3. **Obstacles and iterations** — any verification failures, iteration cycles, re-plans, blocked tasks, or unexpected issues encountered during the run
4. **Insights gained** — non-obvious things learned about the codebase, surprising edge cases discovered, patterns that emerged during implementation
5. **What's left** — open questions, deferred quality feedback, known limitations, or follow-up work suggested by the pipeline

Write it as a narrative (prose paragraphs), not a bullet list. Use the first person plural ("we"). Keep it concise — 3-5 paragraphs, not a report. The goal is to give the developer a sense of connection to the process, not to rehash every detail.

After showing the narrative, re-present the same `AskUserQuestion` menu without the narrative option (since it's already been shown).
