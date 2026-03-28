---
name: rnd-orchestration
description: "Use when coordinating multi-agent R&D pipeline execution — provides pipeline overview, agent roles, information barriers, and gate criteria"
user-invocable: false
effort: medium
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

This framework applies the scientific method to multi-agent coding:

| Scientific Method | Principle | Role |
|---|---|---|
| Hypothesis declaration | Pre-registration | Declare intent + success criteria BEFORE coding |
| Structured experimentation | Hierarchical decomposition | Break tasks into System → Module → Unit with paired verification |
| Blinded peer review | Independent verification | Builder and Verifier are separate — Verifier never sees Builder reasoning |
| Reproducible evidence | Evidence-based gates | No work proceeds without reproducible evidence |
| Dependency analysis | Parallel scheduling | Identify parallel vs sequential work |

## Pipeline Phases & Information Barriers

**Planning** — Decomposes tasks, writes pre-registration docs with testable success criteria. Uses `rnd-framework:rnd-decomposition` skill.
**Scheduling** — Analyzes dependencies, schedules execution waves, enforces iteration budgets.
**Building** — Writes code + tests + honest self-assessment. Uses `rnd-framework:rnd-building` skill. Does NOT verify own work.
**Proof Gate** — Attempts formal Lean 4 proofs of pre-registration criteria. Advisory — results inform verification but do not block the pipeline. Skips when Lean is unavailable.
**Reality Audit** — Adversarially verifies external service contracts (SQL schemas, HTTP endpoints, env vars, SDK behavior). Blocking — INVALID_FOUND routes the task back to building before verification.
**Verification** — Checks output against pre-registered criteria. Uses `rnd-framework:rnd-verification` skill. Does NOT read Builder's self-assessment (enforced by `read-gate.sh` hook). In multi-judge mode, two independent verification passes run sequentially; if they disagree, a third tiebreaker pass receives both reports.
**Integration** — Merges verified outputs, runs integration/system tests. Uses `rnd-framework:rnd-integration` skill.

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
External dependencies:
  - system: [DB | API | file | env | service]
    contract: [What is assumed about this system — schema, response shape, format, presence]
    verification: [How this will be confirmed — e.g., Read actual schema, query endpoint, inspect file sample]
```

## Single-Flow Execution

All pipeline phases run sequentially in one session. No agents are spawned. The session model handles all phases — planning, building, verification, and integration.

> **Note on RND_DIR:** Compute the artifact directory via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`. This outputs an absolute path like `~/.claude/.rnd/<dirname>-<hash>/sessions/<YYYYMMDD-HHMMSS-XXXX>/`. Use `-c` flag to create directory structure.

Skills provide phase-specific discipline:
- Planning: `rnd-framework:rnd-decomposition`
- Building: `rnd-framework:rnd-building`
- Verification: `rnd-framework:rnd-verification`
- Integration: `rnd-framework:rnd-integration`

## Execution Phases

1. **Plan** — Planner decomposes, writes pre-registrations, builds dependency matrix. Planner also writes structured exploration findings to `$RND_DIR/exploration/` (one markdown file per area explored) so downstream agents can read cached context instead of re-exploring the codebase.
2. **Schedule** — Orchestrator creates execution waves from dependency matrix.
3. **Build** — Builder agents work tasks (parallel within waves). Produce code + tests + self-assessment.
3.5. **Proof Gate** (advisory) — Proof-gate agents attempt Lean 4 proofs for each task's criteria. Results (PROVEN/UNPROVEN) are passed to the Verifier as supplementary evidence. Pipeline continues regardless of proof outcomes. Skipped when Lean is unavailable.
3.5b. **Reality Audit** (blocking) — Reality-auditor agents adversarially test each task's external service contracts. INVALID_FOUND routes the task back to the Builder with "expected X, found Y" feedback before Verification proceeds. VALIDATED_ALL, VALIDATED_PARTIAL, and SKIPPED proceed to Verification.
4. **Verify** — Independent Verifier checks each task against pre-registered criteria. PASS/FAIL/ITERATE.
5. **Iterate** — On FAIL, Builder gets feedback only (not fixes). Max 3 cycles, then escalate.
6. **Integrate** — Merge verified outputs, run integration tests, system validation.

## Gate Criteria

**Gate 1 (post-plan):** Every task has complete pre-registration with testable criteria.
**Gate 2 (post-build):** Code + tests + artifacts submitted. Tests pass locally.
**Gate 3 (post-verify):** Verifier PASS on all criteria with evidence.
**Gate 4 (post-integrate):** Integration tests pass. No regressions. System validation passes.

## User Decision Points

When a phase completes and the user needs to decide what happens next, **use `AskUserQuestion` with structured options** instead of open-ended text like "Would you like me to...?". This eliminates decision fatigue.

Rules:
- Always include 2-4 concrete options
- Mark the recommended option first with "(Recommended)" in the label
- Use short, action-oriented labels (e.g., "Fix P0 blockers first", "Verify wave-1", "Re-plan T3")
- Put context in the `description` field, not the label
- Never ask the user to type out what to do next — give them options to pick from

Common decision points:
- **Post-plan:** "Approve plan", "Revise criteria for T2", "Add more tasks"
- **Post-build:** "Verify this wave", "Re-build T3", "Review findings first"
- **Post-verify (mixed results):** "Fix P0 issues first (Recommended)", "Fix all issues", "Ship as-is with known issues"
- **Post-integrate:** "Ship it", "Run another verification pass", "Fix integration failures"

## Scaling Rules

- **Small tasks (<1hr) / quick mode:** Collapse — one Builder + one Verifier (single judge). Lightweight pre-registration.
- **Medium tasks:** Full framework with parallel waves. Use 2-judge consensus verification per task.
- **Large tasks (multi-day):** Add design review gate between Plan and Schedule. Add sub-waves. Use 2-judge consensus verification.
- **Exploratory:** Add Phase 0 — spike 2-3 approaches with time-box before committing.
- **High-stakes:** Multi-judge verification (2 judges + tiebreaker on disagreement). Add formal invariants.
