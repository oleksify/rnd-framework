---
name: rnd-orchestration
description: "Use when coordinating multi-agent R&D pipeline execution — provides pipeline overview, agent roles, information barriers, and gate criteria"
---

# R&D Orchestration Framework

## When to activate
Activate when the user invokes any `/rnd-framework:*` command, mentions "rnd framework", or when you detect a complex multi-step coding task that would benefit from structured decomposition and verification.

## Epistemic Foundation

This is a scientific process. Treat every claim — including your own — with skepticism until proven by evidence.

- **A result is true or false.** There is no "almost true", "mostly works", or "close enough".
- **Evidence must be reproducible.** If you can't reproduce it, it doesn't count.
- **First results are hypotheses, not conclusions.** Tests passing on the first run is a data point, not proof. What about the second run? Edge cases? Adversarial inputs?
- **Disconfirmation over confirmation.** Actively try to break things. A result that survives attempts to disprove it is stronger than one you only tried to confirm.
- **No one is served by false positives.** Passing broken work is worse than blocking correct work. When in doubt, FAIL.

## Framework Overview

This framework combines five core principles for multi-agent coding:

| Layer | Principle | Role |
|---|---|---|
| Decomposition | Structured hierarchical | Break tasks into System → Module → Unit with paired verification |
| Dependencies | Dependency analysis | Identify parallel vs sequential work |
| Quality gates | Verification gates | No work proceeds without passing review |
| Verification | Independent with information barriers | Builder and Verifier are separate — Verifier never sees Builder reasoning |
| Accountability | Spec-first | Declare intent + success criteria BEFORE coding |

## Agent Roles & Information Barriers

**Planner** — Decomposes tasks, writes pre-registration docs with testable success criteria.
**Orchestrator** — Analyzes dependencies, schedules parallel waves, enforces iteration budgets.
**Builder** — Writes code + tests + honest self-assessment. Does NOT verify own work.
**Verifier** — Checks output against pre-registered criteria. Does NOT see Builder's reasoning.
**Integrator** — Merges verified outputs, runs integration/system tests.

### Critical Information Flow Rules

These barriers are what make the framework work. Violating them defeats the purpose.

- Builder → Verifier: Send code, tests, artifacts. BLOCK reasoning, self-assessment, internal notes.
- Verifier → Builder (on fail): Send actionable feedback. BLOCK suggested fixes, internal reasoning.
- The Verifier must assess work purely against the pre-registered spec.

## Pre-Registration Document Format

Every task must have this BEFORE any code is written:

```
Task ID: T<number>
Intent: One sentence — what and why.
Approach: Brief planned implementation.
Expected outputs: Files/functions to produce.
Success criteria:
  - [ ] Specific, testable condition 1
  - [ ] Specific, testable condition 2
Verification level: unit | integration | system
Dependencies: [list of task IDs]
```

## Execution Phases

1. **Plan** — Planner decomposes, writes pre-registrations, builds dependency matrix.
2. **Schedule** — Orchestrator creates execution waves from dependency matrix.
3. **Build** — Builder agents work tasks (parallel within waves). Produce code + tests + self-assessment.
4. **Verify** — Independent Verifier checks each task against pre-registered criteria. PASS/FAIL/ITERATE.
5. **Iterate** — On FAIL, Builder gets feedback only (not fixes). Max 3 cycles, then escalate.
6. **Integrate** — Merge verified outputs, run integration tests, system validation.

## Gate Criteria

**Gate 1 (post-plan):** Every task has complete pre-registration with testable criteria.
**Gate 2 (post-build):** Code + tests + artifacts submitted. Tests pass locally.
**Gate 3 (post-verify):** Verifier PASS on all criteria with evidence.
**Gate 4 (post-integrate):** Integration tests pass. No regressions. System validation passes.

## Scaling Rules

- **Small tasks (<1hr):** Collapse — one Builder + one Verifier. Lightweight pre-registration.
- **Medium tasks:** Full framework with parallel waves.
- **Large tasks (multi-day):** Add design review gate between Plan and Schedule. Add sub-waves.
- **Exploratory:** Add Phase 0 — spike 2-3 approaches with time-box before committing.
- **High-stakes:** Dual independent verification. Add formal invariants.
