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

## Quick Mode (Inline)

**When routing a task to quick mode, execute these steps directly. Do NOT invoke the Skill tool for `/rnd-framework:rnd-quick`.**

1. **Compute RND_DIR:** `RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)`
2. **Write plan:** Save a brief pre-registration to `$RND_DIR/plan.md` — task, approach, success criteria
3. **Build:** Implement the task with tests; follow `rnd-framework:rnd-building` discipline
4. **Verify inline:** Check each success criterion yourself with evidence (run tests, read output, grep for expected patterns). Do NOT spawn a verifier agent — quick mode verifies in the main conversation to avoid rate limits. Save a brief verification note to `$RND_DIR/verifications/T1-verification.md`.
5. **Iterate or ship:** Budget 2 cycles; if exhausted, escalate to `/rnd-framework:rnd-start`

## Data Science Tasks

When a task involves analytical or numerical work — financial calculations, data wiring, chart generation, statistical analysis, or anything requiring Julia or DuckDB — invoke `rnd-framework:rnd-data-science` during the build phase. The pre-registration and verification phases work as normal.

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
