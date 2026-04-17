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

## Execution Mode

Pipeline work runs in specialized subagents spawned via `subagent_type` (e.g., `rnd-builder`, `rnd-verifier`). Each agent has its own model, effort, and preloaded skills; the orchestrator collects results via `SendMessage` and manages phase gates. For the full agent/model/role table, see the project `CLAUDE.md` (§Architecture → Execution Model) — it is already loaded into context.

## Data Science Tasks

When a task involves analytical or numerical work — financial calculations, data wiring, chart generation, statistical analysis, or anything requiring Julia or DuckDB:

Spawn `rnd-data-scientist` instead of `rnd-builder`. The Planner pre-registers as usual; the Verifier checks output as normal.

## Skill Priority

1. **Process skills first** (`rnd-decomposition`, `rnd-debugging`) — determine HOW to approach
2. **Implementation skills second** (`rnd-building`, `rnd-verification`) — guide execution

**Rigid skills** (`rnd-building`, `rnd-verification`, `rnd-debugging`): Follow exactly. **Flexible skills** (`rnd-scaling`, `rnd-completion`): Adapt to context.

## Red Flags

Stop rationalizing: "too simple for R&D" → use `/rnd-framework:rnd-start`; "I'll verify later" → verification is mandatory; "TDD will slow me down" → TDD is faster than debugging; "I already know the approach" → pre-registration prevents scope creep.

## User Interaction

**MANDATORY: When presenting next steps or options to the user, ALWAYS use `AskUserQuestion` with structured choices.** Never write open-ended text like "Would you like me to...?". This is not optional.

- 2-4 concrete options, short action-oriented labels; recommended option listed first
- Context goes in the `description` field, not the label

After finishing any task, always use `AskUserQuestion` to present next steps. Never end with plain text like "Done."

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip the pipeline.
