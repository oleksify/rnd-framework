---
name: using-rnd-framework
description: Use when starting any conversation - establishes how to find and use R&D framework skills, requiring Skill tool invocation before ANY response
effort: low
---

Invoke a skill when it is **likely relevant** to your current task. Use judgment — don't invoke skills speculatively. If a command or agent already has the skill in its frontmatter `skills` list, it is preloaded automatically and does not need a Skill tool call.

**In Claude Code:** Use the `Skill` tool. When you invoke a skill, its content is loaded and presented to you — follow it directly. Never use the Read tool on skill files.

## The Epistemic Rule

This is a scientific process. Results are true or false — never "almost true". Evidence is reproducible or it doesn't exist. Your job is not to please anyone or to reach a quick win. It is to produce correct, verified work.

**Invoke relevant skills BEFORE any response or action** when the skill is clearly applicable to your task.

## Execution Modes

The R&D framework supports two execution modes. Use `/rnd-framework:rnd-start` to select the mode at pipeline start.

### Single-Flow Mode

All pipeline phases (Plan → Build → Verify → Integrate) run sequentially in the current session. No agents are spawned. The session handles all phases directly, with skills providing phase-specific discipline. Best for:

- Small to medium tasks where rate-limit overhead of agent spawning is not justified
- Quick iterations where the main session has sufficient context
- Tasks routed via `/rnd-framework:rnd-quick` (always single-flow)

### Multi-Agent Mode

Pipeline phases are executed by specialized agents spawned as subagents. Each agent has a dedicated role, model assignment, and skill preloading. The orchestrator (main session) coordinates agent spawning, collects results via `SendMessage`, and manages phase gates. Best for:

- Complex multi-task pipelines requiring deep specialization
- High-criticality work where the information barrier must be mechanically enforced between separate agent contexts
- Tasks requiring parallel execution across independent subtasks

**Agent types and their roles:**

| Agent | Model | Role |
|-------|-------|------|
| `rnd-planner` | Opus | Decomposes tasks, builds dependency matrix, writes exploration cache |
| `rnd-builder` | Sonnet | Implements tasks using TDD, produces build manifests and self-assessments |
| `rnd-verifier` | Opus | Independent verification with information barrier, evidence-based verdicts |
| `rnd-integrator` | Sonnet | Wave integration, SHIP/NO-SHIP verdicts, system validation |
| `rnd-debugger` | Opus | Root cause analysis, diagnosis reports, escalation criteria |
| `rnd-proof-gate` | Sonnet | Lean 4 formal proofs of pipeline criteria |
| `rnd-reality-auditor` | Sonnet | Adversarial external contract testing |
| `rnd-data-scientist` | Opus | Julia/DuckDB numerical analysis, financial calculations, chart generation |

In multi-agent mode, agents are spawned using `subagent_type` (e.g., `subagent_type: "rnd-builder"`). Each agent communicates completion and status back to the orchestrator via `SendMessage`.

## Quick Mode (Inline — Single-Flow Only)

**When routing a task to quick mode, execute these steps directly. Do NOT invoke the Skill tool for `/rnd-framework:rnd-quick`.**

1. **Compute RND_DIR:** `RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)`
2. **Write plan:** Save a brief pre-registration to `$RND_DIR/plan.md` — task, approach, success criteria
3. **Build:** Implement the task with tests; follow `rnd-framework:rnd-building` discipline
4. **Verify inline:** Check each success criterion yourself with evidence (run tests, read output, grep for expected patterns). Quick mode verifies in the main conversation — no separate verification phase needed. Save a brief verification note to `$RND_DIR/verifications/T1-verification.md`.
5. **Iterate or ship:** Budget 2 cycles; if exhausted, escalate to `/rnd-framework:rnd-start`

Quick mode is always single-flow. For multi-agent rigor, use `/rnd-framework:rnd-start` and select multi-agent mode.

## Data Science Tasks

When a task involves analytical or numerical work — financial calculations, data wiring, chart generation, statistical analysis, or anything requiring Julia or DuckDB:

- **In multi-agent mode:** Spawn `rnd-data-scientist` instead of `rnd-builder`. The Planner pre-registers as usual; the Verifier checks output as normal.
- **In single-flow mode:** Invoke `rnd-framework:rnd-data-science` during the build phase. The pre-registration and verification phases work as normal.

## Skill Priority

1. **Process skills first** (`rnd-decomposition`, `rnd-debugging`) — determine HOW to approach
2. **Implementation skills second** (`rnd-building`, `rnd-verification`) — guide execution

**Rigid skills** (`rnd-building`, `rnd-verification`, `rnd-debugging`): Follow exactly. **Flexible skills** (`rnd-scaling`, `rnd-completion`): Adapt to context.

## Red Flags

Stop rationalizing: "too simple for R&D" → use `/rnd-framework:rnd-quick`; "I'll verify later" → verification is mandatory; "TDD will slow me down" → TDD is faster than debugging; "I already know the approach" → pre-registration prevents scope creep.

## User Interaction

**MANDATORY: When presenting next steps or options to the user, ALWAYS use `AskUserQuestion`/`AskUser` with structured choices.** Never write open-ended text like "Would you like me to...?". This is not optional. The tool is called `AskUserQuestion` in Claude Code and `AskUser` in Factory Droid — use whichever is available.

- 2-4 concrete options, short action-oriented labels; recommended option listed first
- Context goes in the `description` field, not the label

After finishing any task, always use `AskUserQuestion`/`AskUser` to present next steps. Never end with plain text like "Done."

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip the pipeline.
