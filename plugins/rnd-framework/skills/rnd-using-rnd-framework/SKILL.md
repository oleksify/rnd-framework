---
name: rnd-using-rnd-framework
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

## Exploration & Search

For broad codebase exploration — sweeping many files, directories, or naming conventions to locate code — spawn the `rnd-explorer` agent (`subagent_type: rnd-framework:rnd-explorer`), **never** the built-in `Explore` or `general-purpose` agents. Those inherit the full tool surface (every connected MCP server's schema), so in MCP-heavy sessions they **fail at spawn with "Prompt is too long"** before doing any work. `rnd-explorer` carries a narrow read-only grant (`Read, Grep, Glob, Bash`) that spawns reliably; its final message is the search conclusion. For a single known-location lookup, search inline instead of spawning.

## Tool Discipline

- **Temporary files:** use `$RND_DIR` — never `/tmp`. `$RND_DIR` is auto-allowed and persists across the pipeline.
- **Prefer dedicated tools:** use `Read`/`Write`/`Edit` over shell redirects, `Grep`/`Glob` over `grep`/`find` in Bash — they are reviewable and produce cleaner diffs.

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

## Report Surfacing

When an agent or skill writes a report artifact (`plan.md`, `design-spec.md`, `T<id>-manifest.md`, `T<id>-verification.md`, `wave-<N>-verdict-map.json`, `T<id>-reality-report.md`, `T<id>-diagnosis.md`, `wave-<N>-report.md`, `iteration-log.md`, audit/review reports, narratives, `brainstorm.md`), you MUST print its full path followed by its complete contents verbatim into chat BEFORE any next-step prompt — in the same turn, including in autonomous/loop mode. No length cap, no truncation, no summary substitution. The full Report Surfacing Protocol — including forbidden anti-patterns and the excluded-artifact list — is in the active output style (`scientific.md`, `rigorous.md`, or `pipeline.md`).
