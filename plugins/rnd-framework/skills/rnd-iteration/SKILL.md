---
name: rnd-iteration
description: "Use when handling build-verify feedback loops — receiving verification feedback, iteration budgets, escalation to re-planning"
user-invocable: false
effort: medium
---

# R&D Iteration

## Overview

When the Verifier issues NEEDS ITERATION or FAIL, the Builder gets feedback and revises. This cycle has a budget to prevent infinite rework.

**Core principle:** Feedback describes WHAT is wrong with evidence. The Builder reasons about HOW to fix. Max 3 cycles, then escalate. Repeated iteration on the same criterion is a signal the task needs re-decomposition, not more attempts.

## When to Use

- After a Verifier returns NEEDS ITERATION or FAIL
- When a Builder receives feedback from verification
- When iteration budget is approaching or exceeded

## Information Barrier During Iteration

When passing Verifier feedback to the Builder:

**INCLUDE:**
- The "Feedback" section from the verification report
- Which criteria failed and what evidence showed the failure

**EXCLUDE:**
- The Verifier's internal reasoning
- Suggested fixes (Verifier should not have provided these)
- Other tasks' verification results

## Builder's Response to Feedback

When receiving verification feedback:

1. **Read the feedback carefully** — Understand WHAT failed, not just that it failed
2. **Diagnose** — Use `rnd-framework:rnd-debugging` if the failure is unclear
3. **Fix ALL failed criteria** — Address every criterion marked FAIL or NEEDS ITERATION, not just the primary failure. Use a checklist: list each failed criterion, diagnose it, fix it, and mark it done. Do not move to step 4 until every failed criterion has been addressed.
4. **Check shared code paths** — Identify code paths shared between your fixes and currently-passing criteria. Re-run tests covering those paths to confirm your fixes haven't introduced regressions. If a passing criterion shares logic with a fixed one, explicitly re-verify it.
5. **Re-run ALL tests** — Run the complete test suite, not just tests related to flagged criteria. Fixes often have cross-cutting effects.
6. **Update self-assessment** — Note what changed and why
7. **Resubmit** — Same artifacts, updated code and tests

> **Learning extraction:** After a successful iteration (re-verify returns PASS), the orchestrator extracts the root cause as a gotcha and writes it to the Learning Library via the `rnd-framework:rnd-learning` skill. This closes the feedback loop — the fix that unblocked this task becomes a "Known gotcha" that prevents the same failure in future builds.

## Iteration Budget

| Tier | Max Iterations | Escalation |
|------|---------------|------------|
| Small | 2 | Report to user |
| Standard | 3 | Escalate to re-planning |
| High-stakes | 5 | Escalate to re-planning |

### When Budget Exhausted

If a task fails verification after max iterations:

1. **STOP building** — More hammering won't help
2. **Report to orchestrator:** "Task T<id> exceeded iteration budget"
3. **Likely causes:**
   - Task was decomposed wrong
   - Success criteria were ambiguous
   - The approach is fundamentally flawed
4. **Orchestrator decision:** Re-plan the task, merge it with another task, or escalate to user

**Progress visibility:** When entering an iteration cycle, update the task's `activeForm` via `TaskUpdate` to include the iteration count — e.g., `"Iterating T3 (2/3)"`. This shows progress in the user's task list spinner and prevents the "silent pipeline" problem.

Track all iterations in `$RND_DIR/iteration-log.md` (compute `$RND_DIR` via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` if not set; session is `${CLAUDE_SESSION_ID}`):

```markdown
## T<id> Iteration Log

### Cycle 1
- **Verifier feedback:** [summary]
- **Builder response:** [what was changed]
- **Result:** PASS | FAIL | NEEDS ITERATION

### Cycle 2
...
```

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "One more try will fix it" | You said that last time. Escalate. |
| "The Verifier is being too strict" | Strict is correct. Criteria are binary. If it's not met, it's not met. |
| "The Verifier is wrong" | Maybe. But 3 failures means the task needs re-thinking, not that the Verifier needs convincing. |
| "Just a minor tweak" | If 3 minor tweaks didn't fix it, it's not minor. |
| "It works, the test is just wrong" | Then fix the test and prove it. Claims without evidence are not results. |
| "I'll fix the other failures next round" | No. Address ALL failed criteria in one pass. Narrow fixes burn iteration budget and cause whack-a-mole cycles. Each round must converge, not punt. |

## Related Skills

- `rnd-framework:rnd-debugging` — For diagnosing unclear failures
- `rnd-framework:rnd-building` — Builder methodology
- `rnd-framework:rnd-verification` — Verifier methodology
- `rnd-framework:rnd-decomposition` — For re-planning escalation
