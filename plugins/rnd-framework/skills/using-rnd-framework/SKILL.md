---
name: using-rnd-framework
description: Use when starting any conversation - establishes how to find and use R&D framework skills, requiring Skill tool invocation before ANY response
effort: low
---

Invoke a skill when it is **likely relevant** to your current task. Use judgment — don't invoke skills speculatively. If a command or agent already has the skill in its frontmatter `skills` list, it is preloaded automatically and does not need a Skill tool call.

## How to Access Skills

**In Claude Code:** Use the `Skill` tool. When you invoke a skill, its content is loaded and presented to you — follow it directly. Never use the Read tool on skill files.

# Using the R&D Framework

## The Epistemic Rule

This is a scientific process. Results are true or false — never "almost true". Evidence is reproducible or it doesn't exist. Your job is not to please anyone or to reach a quick win. It is to produce correct, verified work.

**Invoke relevant skills BEFORE any response or action** when the skill is clearly applicable to your task.

## Available Skills

| Skill | When to Use |
|-------|-------------|
| `rnd-framework:rnd-orchestration` | Coordinating multi-agent pipeline execution |
| `rnd-framework:rnd-decomposition` | Breaking tasks into sub-tasks with pre-registration |
| `rnd-framework:rnd-building` | Implementing code with TDD discipline |
| `rnd-framework:rnd-verification` | Independent verification of built work |
| `rnd-framework:rnd-debugging` | Root cause analysis for bugs and failures |
| `rnd-framework:rnd-debug-pipeline` | Running the debug pipeline — 4-phase flow, diagnosis report, escalation criteria, Builder handoff |
| `rnd-framework:rnd-scheduling` | Planning parallel execution waves from dependency analysis |
| `rnd-framework:rnd-iteration` | Handling build-verify feedback loops |
| `rnd-framework:rnd-learning` | Extracting or reading pipeline-discovered gotchas — auto-captures learnings from iteration cycles, injects them into builder prompts |
| `rnd-framework:rnd-scaling` | Choosing pipeline scale for task complexity |
| `rnd-framework:rnd-roadmapping` | Planning multi-session work — milestone decomposition, progress tracking, and roadmap lifecycle |
| `rnd-framework:rnd-integration` | Merging verified outputs, system validation |
| `rnd-framework:rnd-completion` | Post-SHIP branch management and PR creation |
| `rnd-framework:rnd-formatting` | Use before doc-polish and committing — detects the project's formatter and runs it on pipeline-changed files |
| `rnd-framework:rnd-doc-polish` | Use after formatting, before committing — checks and updates CLAUDE.md, README.md, project docs, and stale inline comments |
| `rnd-framework:writing-skills` | Creating new skills for the framework |
| `rnd-framework:prefer-system-tools` | Check if a native CLI tool can do the job before writing a script |
| `rnd-framework:bun-scripting` | Writing helper scripts — prefer Bun over Python when available |
| `rnd-framework:committing` | Creating git commits — message style, length limits, user confirmation |
| `rnd-framework:rnd-data-science` | Performing numerical analysis, financial calculations, data wiring, chart generation, or any analytical task requiring Julia or DuckDB computation |
| `rnd-framework:rnd-multi-judge` | Running multi-judge consensus verification — spawning 2 independent verifiers, aggregating verdicts, and triggering a tiebreaker on disagreement |
| `rnd-framework:rnd-local-experts` | Discovering project-local agents and skills in `.claude/agents/` and `.claude/skills/` and surfacing them for the Planner to reference in pre-registrations |
| `rnd-framework:rnd-design` | Use when exploring architectural alternatives before planning — generates 2-3 approaches with trade-offs and produces a design spec |
| `rnd-framework:rnd-failure-modes` | Use when verifying — catalog of known verification anti-patterns and red-flag phrases to watch for |
| `rnd-framework:rnd-slop-detection` | Use when reviewing code quality — scores code for LLM anti-patterns (over-commenting, cargo-cult error handling, unnecessary abstractions) with evidence-based verdicts |
| `rnd-framework:rnd-standards` | Use at pipeline start to extract project-specific coding rules from CLAUDE.md files and convert them into regex-based slop patterns saved to `$RND_DIR/project-patterns.json` |
| `rnd-framework:code-review` | Use when reviewing code changes — defines the six review categories, four severity levels, verdict taxonomy (CLEAN/ISSUES_FOUND/CRITICAL_ISSUES), and structured report format |
| `rnd-framework:kiss-practices` | Language-specific KISS rules to prevent over-engineering — load during Phase 0 discovery, read only the relevant language files |
| `rnd-framework:fp-practices` | Functional programming principles — pure functions, data transformations, composition, command-query separation, immutability |
| `rnd-framework:rnd-experiments` | Use when verifying — defines how verifiers write independent experiment tests from the spec alone |
| `rnd-framework:rnd-reality-auditing` | Use when running adversarial verification of external service contracts — defines how to identify external interactions, design disproving experiments, and produce reality reports with VALID/INVALID/UNCHECKED verdicts |
| `rnd-framework:lean-proving` | Use when verifying mathematical properties of Builder code using Lean 4 — translates pre-registration criteria into formal theorems, generates companion tests, runs lake build, and produces T<id>-proof-report.md for the Verifier |
| `rnd-framework:rnd-calibration` | Use when recording verdict data — JSONL-based calibration stats with automatic false-verdict detection |

## Available Commands

| Command | Purpose |
|---------|---------|
| `/rnd-framework:start <task>` | Full pipeline: Plan → Build → Verify → Integrate |
| `/rnd-framework:plan <task>` | Planning only — decompose and pre-register |
| `/rnd-framework:roadmap` | Plan and manage multi-session roadmaps for large tasks spanning multiple days |
| `/rnd-framework:build <target>` | Build a task or wave |
| `/rnd-framework:verify <target>` | Independent verification |
| `/rnd-framework:review` | Review code changes with multi-judge evidence-based rigor — detects architecture, security, correctness, testing, KISS, and style issues |
| `/rnd-framework:audit` | Full codebase audit against project standards |
| `/rnd-framework:integrate <target>` | Merge and integration testing |
| `/rnd-framework:status` | Pipeline status dashboard |
| `/rnd-framework:quick <task>` | Lightweight mode for small tasks |
| `/rnd-framework:history` | Browse past pipeline sessions for this project |
| `/rnd-framework:resume` | Resume a partially-completed pipeline from where it left off |
| `/rnd-framework:validate` | Validate plugin structure, frontmatter, and cross-references |
| `/rnd-framework:doctor` | Runtime environment diagnostics — CLI tools, hooks, RND_DIR, version sync |
| `/rnd-framework:bump` | Bump patch version, prepend CHANGELOG entry, stage and commit |
| `/rnd-framework:brainstorm` | Conversational idea exploration — funnels vague ideas into focused, implementable plans |
| `/rnd-framework:narrative` | Generate a development narrative for a pipeline session from its artifacts |
| `/rnd-framework:debug` | Debug pipeline: reproduce, diagnose, fix, verify |
| `/rnd-framework:calibrate` | Record manual ground-truth verdict corrections for calibration |

## Quick Mode (Inline)

**When routing a task to quick mode, execute these steps directly. Do NOT invoke the Skill tool for `/rnd-framework:quick`.**

1. **Compute RND_DIR:** `RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)` then `bun "${CLAUDE_PLUGIN_ROOT}/lib/extract-patterns.ts" "$RND_DIR"`
2. **Write plan:** Save a brief pre-registration to `$RND_DIR/plan.md` — task, approach, success criteria
3. **Build:** Implement the task with tests; follow `rnd-framework:rnd-building` discipline
4. **Verify inline:** Check each success criterion yourself with evidence (run tests, read output, grep for expected patterns). Do NOT spawn a verifier agent — quick mode verifies in the main conversation to avoid rate limits. Save a brief verification note to `$RND_DIR/verifications/T1-verification.md`.
5. **Iterate or ship:** Budget 2 cycles; if exhausted, escalate to `/rnd-framework:start`

For the full `/rnd-framework:quick` experience (task suggestions, detailed iteration handling), invoke it directly.

## Data Science Tasks

When a task involves analytical or numerical work — financial calculations, data wiring, chart generation, statistical analysis, or anything requiring Julia or DuckDB as a computation backend — use the **`rnd-data-scientist` agent as a standalone specialist**. This agent replaces the standard Build phase for that task:

- The Planner decomposes and pre-registers the task as usual
- Instead of spawning `rnd-builder`, spawn `rnd-data-scientist` for the analytical task
- The Verifier then independently checks the output as normal

Do not route analytical tasks through `rnd-builder` — the data-scientist agent has the specialized skills and tooling for numerical correctness.

## Pipeline Scaling

Every task goes through the R&D pipeline, scaled to complexity:

| Task Size | Entry Point | What Happens |
|-----------|-------------|--------------|
| Trivial | `/rnd-framework:quick` | Inline plan → build → verify (single verifier) |
| Small (<1hr) | `/rnd-framework:quick` | 1 Builder + 1 Verifier |
| Medium | `/rnd-framework:start` | Planner + Builders + 2-judge verification + Integrator |
| Large | `/rnd-framework:start` | Full pipeline + design review gate + multi-judge verification |
| High-stakes | `/rnd-framework:start` | Full pipeline + dual verification |

## Skill Priority

When multiple skills could apply:

1. **Process skills first** (`rnd-decomposition`, `rnd-debugging`) — these determine HOW to approach
2. **Implementation skills second** (`rnd-building`, `rnd-verification`) — these guide execution

"Build X" → `rnd-decomposition` first, then `rnd-building`.
"Fix this bug" → `rnd-debugging` first, then `rnd-building`.

## Skill Types

**Rigid** (`rnd-building`, `rnd-verification`, `rnd-debugging`): Follow exactly. Don't adapt away discipline.

**Flexible** (`rnd-scaling`, `rnd-completion`): Adapt principles to context.

## Red Flags

These thoughts mean STOP — you're rationalizing:

| Thought | Reality |
|---------|---------|
| "This is too simple for R&D" | Use `/rnd-framework:quick`. The pipeline scales down. |
| "I need more context first" | Skill check comes BEFORE exploration. |
| "Let me just fix this quickly" | Quick fixes without verification create debt. |
| "I'll verify later" | Verification is not optional. It's the whole point. |
| "I already know the approach" | Pre-registration prevents scope creep. |
| "TDD will slow me down" | TDD is faster than debugging. |

## User Interaction

**MANDATORY: When presenting next steps or options to the user, ALWAYS use `AskUserQuestion` with structured choices.** Never write open-ended text like "Would you like me to...?" or "Want me to start fixing these?". This is not optional.

- 2-4 concrete options, short action-oriented labels
- Recommended option listed first with "(Recommended)" in the label
- Context goes in the `description` field, not the label
- The user picks — you don't ask them to explain what to do

This applies at EVERY decision point: post-plan, post-build, post-verify, post-integrate, after completing a user request, and any time you need user input on direction.

### After completing a task

When you finish a user's request — whether it was a pipeline run, an ad-hoc fix, or any other task — **always** use `AskUserQuestion` to present next steps. Typical options include:

- Continuing with related work (e.g., "Fix another issue", "Add tests for the change")
- Session management (e.g., "Finish session" via `rnd-dir.sh --finish`)
- Review options (e.g., "Review what changed", "Check git status")

Tailor options to what just happened. Never end with plain text like "Done." or "Let me know if you need anything else."

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip the pipeline.
