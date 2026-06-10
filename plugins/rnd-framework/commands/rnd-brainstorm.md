---
description: "Brainstorm and refine a vague idea into a focused, implementable plan through structured conversational questioning."
argument-hint: "[vague idea or topic | empty to start from scratch]"
effort: medium
---

# R&D Framework: Brainstorm

A conversational pipeline for idea exploration. No build or verify pipeline agents, no code — just structured questioning that funnels a vague idea into a focused design plan ready for `/rnd-framework:rnd-start`. (Grounding the conversation in the codebase is fine; when it needs a broad sweep, use the read-only `rnd-framework:rnd-explorer` — see Guidelines.)

## Setup

```bash
RND_DIR=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" -c)
```

> **Model advisory:** Brainstorming benefits from maximum reasoning depth. Run this command with a Fable 5 session and set effort to `high` or above for best results — shallow reasoning during the ideation phase tends to surface obvious options and miss the tricky constraints that matter most. If the session is already running a lighter model, the structured phases below will still work, but expect to iterate more on Phase 4 scope decisions.

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

Based on the expanded understanding, identify **2-4 meaningfully different directions** the idea could go. These are not implementation approaches (that's `/rnd-framework:rnd-start`'s design phase) — they're conceptual directions.

**Before generating directions, do this private step:** name the first, most-obvious direction — the one an LLM trained on the popular literature would suggest by default ("use library X", "build a CRUD UI", "add a LangChain agent", "wrap it in a microservice"). Call this the **baseline**. Your job in this phase is NOT to present the baseline as the "safe default" — your job is to diverge from it and force the user to see what lies off the well-trodden path.

Then produce the 2-4 directions under these rules:

- **At least one direction must be a road-less-traveled angle** — a genuinely different framing that most developers (and most LLMs) would not suggest first. Examples: inverting the data flow, replacing a stateful component with a pure function, using a legacy/unfashionable primitive that fits better than the trendy one, dropping a feature instead of building it, building nothing and changing the workflow instead.
- **At least one direction should explicitly question the problem framing** — a direction where the "right" move is to reshape what the user thinks they need (e.g., "what if this isn't a feature, it's a documentation gap?").
- **The baseline direction is optional.** Only include it if it's genuinely competitive on the stated priorities. If you include it, label it honestly (e.g., "The conventional approach — do the thing most projects would do here") rather than dressing it up as insight.
- **Alternatives must be meaningfully different** — not surface variations of the same approach dressed up with different names.

For each direction, provide:
- **Name:** Short, memorable label
- **One sentence:** What this direction means
- **What it prioritizes:** What trade-off does it make?
- **Why it's non-obvious (if applicable):** For the road-less-traveled direction(s), one sentence on why someone wouldn't reach for this first and why it might still be right here.

Present all directions and use `AskUserQuestion`:
> "Which direction resonates most?"

Options: one per direction (max 3 directions), plus "Combine, reframe, or describe a different direction" as the final option — total ≤4 options.

If the user wants to combine or reframe, adapt and re-present. Max 2 rounds of exploration before moving to Phase 4.

## Phase 4: Narrow

Deep-dive on the chosen direction. Ask 4-6 targeted questions using `AskUserQuestion` with 2–4 options per question:

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

- [ ] Implement via `/rnd-framework:rnd-start [paste this plan]`
- [ ] Or save for later and revisit
```

Present the plan as regular text output (not abbreviated). Then proceed to Phase 6.

## Phase 6: Output

**MANDATORY: You MUST invoke `AskUserQuestion` to present next-step options. Do NOT end the brainstorming session with a plain-text message (e.g., "Plan saved to X. Kick off the pipeline with /rnd-framework:rnd-start ..."). Leaving a text message instead of asking is a defect — the user must always be presented with selectable options.**

Use `AskUserQuestion` to present options:

- "Implement now with /rnd-framework:rnd-start (Recommended)" — save the plan to `$RND_DIR/brainstorm.md` and immediately invoke `/rnd-framework:rnd-start` with the plan as the task description
- "Save for later" — save the plan to `$RND_DIR/brainstorm.md` and tell the user the file path so they can reference it in a future session
- "Refine further" — go back to Phase 4 with additional questions (max 2 refinement rounds)
- "Discard" — don't save anything; the brainstorming session ends

If the user chooses "Save for later," also offer to save to a project-local location via a follow-up `AskUserQuestion`:
- "Save to `$RND_DIR/brainstorm.md` (default)"
- "Save to a project file like `docs/brainstorm-[topic].md`"

## Guidelines

- **No pipeline phases.** This is a conversation between you and the user. Do not run Build, Verify, Plan, or any other pipeline phase.
- **No code.** Do not write or modify any project files during brainstorming. The output is a plan, not code.
- **Grounding & exploration.** "No agents" above means no *build/verify pipeline* agents — it does **not** forbid reading the codebase to ground the conversation. When grounding needs a broad codebase sweep (mapping an architecture, finding where something lives across many files), spawn `rnd-framework:rnd-explorer` — **never** the built-in `Explore` or `general-purpose` agents. Those inherit the full MCP tool surface and fail at spawn with "Prompt is too long" in MCP-heavy sessions; `rnd-explorer` carries a narrow read-only grant and spawns reliably. For a single known-location lookup, read inline instead of spawning.
- **Use AskUserQuestion for every question.** Never ask questions as plain text. Every question must be structured with options.
- **Cap options at 4 per question.** `AskUserQuestion` enforces a hard limit of ≤4 options per question and will error on any call that exceeds it. Every `AskUserQuestion` call in this command must produce at most 4 options.
- **Never end with a plain-text message.** Every phase that requires a user decision — including the final Phase 6 output — MUST use `AskUserQuestion`. Writing "Plan saved to X. Run /rnd-framework:rnd-start ..." as the terminal response is a defect. The user must always receive selectable options, not a suggestion to run a command themselves.
- **Be opinionated.** Offer concrete suggestions and push back constructively. A brainstorming partner who agrees with everything is useless.
- **Diverge before you converge.** The LLM-default is to regress to the mean — the most popular framing, the most common library, the approach you've seen a hundred times in training data. In Phase 3, actively resist this. Identify the obvious answer, then find what's on the other side of it.
- **Keep momentum.** Each phase should take 1-2 question rounds, not 10. The total session should be 5-8 questions, not 20.
- **Respect the funnel.** Go broad first (Phase 2), then narrow (Phase 4). Don't jump to implementation details in Phase 2.

## Output Discipline

This command produces `brainstorm.md` (Phase 5/6) under `$RND_DIR/`. Surface it per the **Report Surfacing Protocol** in your active output style: print the file path followed by the file's complete contents verbatim BEFORE the Phase 6 `AskUserQuestion` — in the same turn, including in autonomous/loop mode. "Plan saved to `$RND_DIR/brainstorm.md`. Pick an option:" without printing the file verbatim is a defect.

**Do NOT wrap the body in a fenced code block.** The Phase 5 ` ```markdown ` block above (lines 94–131) shows the file *structure* the model should write — it is illustrative-only and is NOT a presentation directive. When surfacing the actual brainstorm.md to the user, emit: the path in single backticks, a blank line, then the body as bare Markdown with no surrounding ` ```markdown ` / ` ``` ` fence and no 4-space indent. Wrapping the body in a fence makes headings, bold, and inline code render as literal text — the exact failure mode this discipline prevents.
