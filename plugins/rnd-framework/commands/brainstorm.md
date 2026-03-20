---
description: "Brainstorm and refine a vague idea into a focused, implementable plan through structured conversational questioning."
argument-hint: "[vague idea or topic | empty to start from scratch]"
effort: medium
---

# R&D Framework: Brainstorm

A conversational pipeline for idea exploration. No agents, no building — just structured questioning that funnels a vague idea into a focused design plan ready for `/rnd-framework:start`.

## Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

## Phase 1: Seed

Get the initial idea on the table.

If `$ARGUMENTS` is non-empty, use it as the seed idea and proceed to Phase 2.

If `$ARGUMENTS` is empty, use `AskUserQuestion` to ask:
> "What's on your mind? Describe an idea, problem, or area you want to explore — it can be vague."

Options:
- "I have a feature idea" — a new capability to add to something
- "I have a problem to solve" — something broken or missing that needs fixing
- "I want to improve something" — an existing thing that could be better
- "I want to explore a space" — a broad area to think about

The user will either pick an option and elaborate, or type their idea directly. Whatever they provide becomes the **seed**.

## Phase 2: Expand

Understand the space around the seed. Ask 4-6 broad questions using `AskUserQuestion` (can be batched into 2-3 multi-question rounds). Cover:

- **Who benefits?** Who is the user/audience/stakeholder? What do they care about?
- **What exists today?** What's the current state? What works, what doesn't?
- **Why now?** What's the trigger? Is there urgency or a deadline?
- **What constraints exist?** Technical, time, budget, skill, compatibility?
- **What's the dream outcome?** If this worked perfectly, what would it look like?
- **What's been tried?** Any prior approaches, rejected ideas, or lessons learned?

Provide 2-4 concrete options per question based on what you can infer from the seed and codebase context. Let the user refine or override.

After this phase, summarize what you've learned in 3-5 bullet points and confirm with the user: "Does this capture it?"

## Phase 3: Explore

Based on the expanded understanding, identify **2-4 meaningfully different directions** the idea could go. These are not implementation approaches (that's `/rnd-framework:start`'s design phase) — they're conceptual directions.

For each direction, provide:
- **Name:** Short, memorable label
- **One sentence:** What this direction means
- **What it prioritizes:** What trade-off does it make?

Present all directions and use `AskUserQuestion`:
> "Which direction resonates most?"

Options: one per direction, plus "Combine elements from multiple" and "None of these — let me describe what I want."

If the user wants to combine or reframe, adapt and re-present. Max 2 rounds of exploration before moving to Phase 4.

## Phase 4: Narrow

Deep-dive on the chosen direction. Ask 4-6 targeted questions using `AskUserQuestion`:

- **Scope:** What's the minimum viable version? What can be deferred?
- **Priorities:** If you had to pick 2-3 things that matter most, what are they?
- **Trade-offs:** What are you willing to sacrifice? Speed vs quality? Features vs simplicity?
- **Integration:** How does this fit with what already exists?
- **Risks:** What could go wrong? What's the biggest unknown?
- **Success criteria:** How would you know this worked?

These questions should be specific to the chosen direction — not generic. Reference the codebase, the user's earlier answers, and the direction's priorities.

## Phase 5: Focus

Synthesize everything into a **focused design plan**. Write it as structured markdown:

```markdown
# Brainstorm: [Title]

## Problem Statement

[2-3 sentences: what problem this solves and for whom]

## Scope

**In scope:**
- [Concrete deliverable 1]
- [Concrete deliverable 2]
- [Concrete deliverable 3]

**Out of scope (for now):**
- [Deferred item 1]
- [Deferred item 2]

## Approach

[3-5 bullet points describing the high-level approach — not implementation details, but the strategy]

## Priorities

1. [Most important thing]
2. [Second most important]
3. [Third]

## Open Questions

- [Unresolved question 1]
- [Unresolved question 2]

## Next Steps

- [ ] Implement via `/rnd-framework:start [paste this plan]`
- [ ] Or save for later and revisit
```

Present the plan as regular text output (not abbreviated). Then proceed to Phase 6.

## Phase 6: Output

Use `AskUserQuestion` to present options:

- "Implement now with /rnd-framework:start (Recommended)" — save the plan to `$RND_DIR/brainstorm.md` and suggest the user run `/rnd-framework:start` with the plan as the task description
- "Save for later" — save the plan to `$RND_DIR/brainstorm.md` and tell the user the file path so they can reference it in a future session
- "Refine further" — go back to Phase 4 with additional questions (max 2 refinement rounds)
- "Discard" — don't save anything; the brainstorming session ends

If the user chooses "Save for later," also offer to save to a project-local location:
> "Save to `$RND_DIR/brainstorm.md` (default) or to a project file like `docs/brainstorm-[topic].md`?"

## Guidelines

- **No agents.** This is a conversation between you and the user. Do not spawn Builder, Verifier, Planner, or any other agent.
- **No code.** Do not write or modify any project files during brainstorming. The output is a plan, not code.
- **Use AskUserQuestion for every question.** Never ask questions as plain text. Every question must be structured with options.
- **Be opinionated.** Offer concrete suggestions and push back constructively. A brainstorming partner who agrees with everything is useless.
- **Keep momentum.** Each phase should take 1-2 question rounds, not 10. The total session should be 5-8 questions, not 20.
- **Respect the funnel.** Go broad first (Phase 2), then narrow (Phase 4). Don't jump to implementation details in Phase 2.
