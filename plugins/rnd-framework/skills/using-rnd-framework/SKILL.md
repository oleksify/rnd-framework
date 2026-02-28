---
name: using-rnd-framework
description: Use when starting any conversation - establishes how to find and use R&D framework skills, requiring Skill tool invocation before ANY response
---

<EXTREMELY-IMPORTANT>
If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill.

IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.

This is not negotiable. This is not optional. You cannot rationalize your way out of this.
</EXTREMELY-IMPORTANT>

## How to Access Skills

**In Claude Code:** Use the `Skill` tool. When you invoke a skill, its content is loaded and presented to you — follow it directly. Never use the Read tool on skill files.

# Using the R&D Framework

## The Epistemic Rule

This is a scientific process. Results are true or false — never "almost true". Evidence is reproducible or it doesn't exist. Your job is not to please anyone or to reach a quick win. It is to produce correct, verified work.

**Invoke relevant skills BEFORE any response or action.** Even a 1% chance a skill might apply means you should invoke it.

## Available Skills

| Skill | When to Use |
|-------|-------------|
| `rnd-framework:rnd-orchestration` | Coordinating multi-agent pipeline execution |
| `rnd-framework:rnd-decomposition` | Breaking tasks into sub-tasks with pre-registration |
| `rnd-framework:rnd-building` | Implementing code with TDD discipline |
| `rnd-framework:rnd-verification` | Independent verification of built work |
| `rnd-framework:rnd-debugging` | Root cause analysis for bugs and failures |
| `rnd-framework:rnd-scheduling` | Planning parallel execution waves from dependency analysis |
| `rnd-framework:rnd-iteration` | Handling build-verify feedback loops |
| `rnd-framework:rnd-scaling` | Choosing pipeline scale for task complexity |
| `rnd-framework:rnd-integration` | Merging verified outputs, system validation |
| `rnd-framework:rnd-completion` | Post-SHIP branch management and PR creation |
| `rnd-framework:rnd-isolation` | Using git worktrees for builder isolation |
| `rnd-framework:writing-skills` | Creating new skills for the framework |
| `rnd-framework:prefer-system-tools` | Check if a native CLI tool can do the job before writing a script |
| `rnd-framework:bun-scripting` | Writing helper scripts — prefer Bun over Python when available |
| `rnd-framework:committing` | Creating git commits — message style, length limits, user confirmation |

## Available Commands

| Command | Purpose |
|---------|---------|
| `/rnd-framework:start <task>` | Full pipeline: Plan → Build → Verify → Integrate |
| `/rnd-framework:plan <task>` | Planning only — decompose and pre-register |
| `/rnd-framework:build <target>` | Build a task or wave |
| `/rnd-framework:verify <target>` | Independent verification |
| `/rnd-framework:integrate <target>` | Merge and integration testing |
| `/rnd-framework:status` | Pipeline status dashboard |
| `/rnd-framework:quick <task>` | Lightweight mode for small tasks |

## Pipeline Scaling

Every task goes through the R&D pipeline, scaled to complexity:

| Task Size | Entry Point | What Happens |
|-----------|-------------|--------------|
| Trivial | `/rnd-framework:quick` | Inline plan → build → verify |
| Small (<1hr) | `/rnd-framework:quick` | 1 Builder + 1 Verifier |
| Medium | `/rnd-framework:start` | Planner + Builders + Verifiers + Integrator |
| Large | `/rnd-framework:start` | Full pipeline + design review gate |
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

This applies at EVERY decision point: post-plan, post-build, post-verify, post-integrate, and any time you need user input on direction.

## User Instructions

Instructions say WHAT, not HOW. "Add X" or "Fix Y" doesn't mean skip the pipeline.
