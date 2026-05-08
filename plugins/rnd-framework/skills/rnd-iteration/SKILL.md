---
name: rnd-iteration
description: "Use when handling build-verify feedback loops — receiving verification feedback, iteration budgets, escalation to re-planning"
user-invocable: false
effort: medium
---

# R&D Iteration

## Overview

When the Verifier issues NEEDS ITERATION or FAIL, the Builder gets feedback and revises. This cycle has a budget to prevent infinite rework.

**Core principle:** Feedback describes WHAT is wrong with evidence. The Builder reasons about HOW to fix. Repeated iteration on the same criterion is a signal the task needs re-decomposition, not more attempts.

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

### Wave-Scoped Budget

Iteration is wave-scoped: the budget for a wave rebuild equals the per-task budget of the highest-criticality task in the wave. All failing tasks in the wave are rebuilt in a single pass; re-verification covers the full wave. One cycle = one wave rebuild + one wave re-verify.

Example: a wave containing LOW and NORMAL tasks uses NORMAL budget (3 iterations max).

### When Budget Exhausted

If a wave still has failures after max iterations:

1. **STOP building** — More hammering won't help
2. **Report to orchestrator:** "Wave <N> exceeded iteration budget"
3. **Likely causes:**
   - Tasks were decomposed wrong
   - Success criteria were ambiguous
   - The approach is fundamentally flawed
4. **Orchestrator decision:** Re-plan failing tasks, skip them, or escalate to user

**Progress visibility:** When entering a wave iteration cycle, update the wave's active tasks via `TaskUpdate` to include the iteration count — e.g., `"Iterating Wave <N> (2/3)"`. This shows progress in the user's task list spinner and prevents the "silent pipeline" problem.

Track wave iterations in `$RND_DIR/iteration-log.md` (compute `$RND_DIR` via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` if not set; session is `${CLAUDE_SESSION_ID}`):

```markdown
## Wave-<N> Iteration Log

### Cycle 1
- **Failing tasks:** [T<id>, T<id>, ...]
- **Wave failure report:** [summary of per-task verdict map sent to Builder]
- **Builder response:** [what was changed across all failing tasks]
- **Result:** PASS | NEEDS_ITERATION | FAIL

### Cycle 2
...

#### T<id> detail
- **Criterion failed:** [criterion text]
- **Evidence:** [evidence summary]
- **Fix applied:** [what Builder changed]
```

## AMEND_REQUIRED Divergence

`AMEND_REQUIRED` is a distinct verdict that routes outside the normal iteration loop. It does **not** mean "try harder" — it means the Verifier believes the pre-registration itself may be wrong.

### Routing

- `AMEND_REQUIRED` → routes to the **rnd-amendment-arbiter** agent, not the Builder
- `ESCALATE_REPLAN` (arbiter output) → routes to a **Planner micro-spawn**; the task is re-decomposed, not reworked in-place

The Builder does **not** act on an `AMEND_REQUIRED` verdict until the arbiter + user gate has resolved.

### Budget rules

| Event | Iteration count |
|-------|----------------|
| `AMEND_REQUIRED` issued | Does **not** consume an iteration |
| Amendment approved → re-verify | Does **not** consume an iteration (re-verifies against amended criteria as a fresh run) |
| Amendment rejected → reverts to `NEEDS_ITERATION` | **Consumes** one iteration from the task's budget |

Amendment cycles are off-budget by design. The pipeline pauses at the arbiter, not at the Builder. Only rejection — which forces the Builder back into the normal iteration loop — counts against the budget.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "One more try will fix it" | You said that last time. Escalate. |
| "The Verifier is being too strict" | Strict is correct. Criteria are binary. If it's not met, it's not met. |
| "The Verifier is wrong" | Maybe. But 3 failures means the task needs re-thinking, not that the Verifier needs convincing. |
| "Just a minor tweak" | If 3 minor tweaks didn't fix it, it's not minor. |
| "It works, the test is just wrong" | Then fix the test and prove it. Claims without evidence are not results. |
| "I'll fix the other failures next round" | No. Address ALL failed criteria in one pass. Narrow fixes burn iteration budget and cause whack-a-mole cycles. Each round must converge, not punt. |
| "The Verifier issued AMEND_REQUIRED" | This is not a free retry; the arbiter still evaluates whether the spec or the code is wrong. |

## Amendment Log Artifact

When a Verifier issues `AMEND_REQUIRED`, the amendment-arbiter writes an amendment log to `$RND_DIR/briefs/T<id>-amendments.md`. This file is barrier-protected — Verifier and proof-gate agents cannot read it.

### Path pattern

```
$RND_DIR/briefs/T<id>-amendments.md
```

### Append-only protocol

Each `AMEND_REQUIRED` cycle appends one entry to the file. Entries are never edited or deleted. The file grows as a chronological record of all amendment proposals for that task.

### Required fields per entry

```markdown
## Amendment — <ISO 8601 timestamp>

**Cited defect:** <Verifier's exact cited defect from the AMEND_REQUIRED verdict's `feedback` field>

**Arbiter recommendation:** AMEND | REBUILD | ESCALATE_REPLAN

**Arbiter output:**
<full structured output from the arbiter — AMEND field patches, REBUILD rationale, or ESCALATE_REPLAN rationale>

**User decision:** approved | rejected
```

### AMEND_REQUIRED vs NEEDS_ITERATION

`AMEND_REQUIRED` is NOT an iteration cycle. It does NOT consume iteration budget. It routes through the arbiter + user gate, mutates the pre-reg (on approval), and re-verifies against the amended criteria as if it were a fresh verification. The iteration budget counter for the task does not increment.

If the user rejects the amendment proposal, the verdict reverts to `NEEDS_ITERATION` and the normal iteration budget applies.

## Related Skills

- `rnd-framework:rnd-debugging` — For diagnosing unclear failures
- `rnd-framework:rnd-building` — Builder methodology
- `rnd-framework:rnd-verification` — Verifier methodology
- `rnd-framework:rnd-decomposition` — For re-planning escalation
