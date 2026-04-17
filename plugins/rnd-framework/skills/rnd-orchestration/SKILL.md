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

This framework applies the scientific method to structured coding:

| Scientific Method | Principle | Role |
|---|---|---|
| Hypothesis declaration | Pre-registration | Declare intent + success criteria BEFORE coding |
| Structured experimentation | Hierarchical decomposition | Break tasks into System → Module → Unit with paired verification |
| Blinded peer review | Independent verification | Builder and Verifier are separate — Verifier never sees Builder reasoning |
| Reproducible evidence | Evidence-based gates | No work proceeds without reproducible evidence |
| Dependency analysis | Parallel scheduling | Identify parallel vs sequential work |

## Agent Roles & Information Barriers

The framework defines 8 specialized agent roles. Dedicated agents are spawned for each role.

**Planner** — Decomposes tasks, writes pre-registration docs with testable success criteria. Uses `rnd-framework:rnd-decomposition` skill.
**Orchestrator** — Analyzes dependencies, schedules parallel waves, enforces iteration budgets. Uses `rnd-framework:rnd-orchestration` skill.
**Builder** — Writes code + tests + honest self-assessment. Uses `rnd-framework:rnd-building` skill. Does NOT verify own work.
**Proof Gate** — Attempts formal Lean 4 proofs of pre-registration criteria. Advisory — results inform the Verifier but do not block the pipeline. Skips when Lean is unavailable.
**Reality Auditor** — Adversarially verifies external service contracts (SQL schemas, HTTP endpoints, env vars, SDK behavior). Blocking — INVALID_FOUND routes the task back to the Builder before the Verifier sees it.
**Verifier** — Checks output against pre-registered criteria. Uses `rnd-framework:rnd-verification` skill. Does NOT read Builder's self-assessment (enforced by `read-gate.sh` hook). In multi-judge mode, two independent Verifiers run in parallel; if they disagree, a third **Tiebreaker** Verifier receives both reports (but never self-assessments) and issues the final verdict.
**Integrator** — Merges verified outputs, runs integration/system tests. Uses `rnd-framework:rnd-integration` skill.
**Data Scientist** — Handles numerical analysis, financial calculations, data wiring, chart generation. Uses `rnd-framework:rnd-data-science` skill. Spawned on-demand when the task requires Julia, DuckDB, or statistical analysis.

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
  Correctness:
  - [ ] Specific, testable condition 1
  Quality:
  - [ ] Specific, testable condition 2
Verification level: unit | integration | system
Dependencies: [list of task IDs]
Preconditions:
  - [File/content assertion verified before build starts — omit if none]
External dependencies:
  - system: [DB | API | file | env | service]
    contract: [What is assumed about this system — schema, response shape, format, presence]
    verification: [How this will be confirmed — e.g., Read actual schema, query endpoint, inspect file sample]
fulfills: [VAL-AREA-NNN, ...]
```

## Execution Mode

Dedicated agents are spawned for each pipeline role. The orchestrator session coordinates them, enforcing information barriers and gate criteria.

Agent assignments:
- **rnd-planner** — Planning phase (Opus model)
- **rnd-builder** — Build phase (Sonnet model)
- **rnd-proof-gate** — Proof Gate phase (Sonnet model, advisory)
- **rnd-reality-auditor** — Reality Audit phase (Sonnet model, blocking)
- **rnd-verifier** — Verification phase (Opus model, Edit disallowed)
- **rnd-integrator** — Integration phase (Sonnet model)
- **rnd-data-scientist** — On-demand for analytical tasks (Opus model)
- **rnd-debugger** — On-demand for root cause analysis (Opus model)

> **Note on RND_DIR:** Compute the artifact directory via `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"`. This outputs an absolute path like `~/.claude/.rnd/<dirname>-<hash>/sessions/<YYYYMMDD-HHMMSS-XXXX>/`. Use `-c` flag to create directory structure.

## Subagent Coordination

### Agent Permission Mode

All pipeline agents are spawned with `mode: "acceptEdits"`:

- **Planner** — decomposes tasks and writes pre-registrations
- **Builder** — implements tasks with TDD discipline
- **Verifier** — independently checks outputs against pre-registered criteria
- **Integrator** — merges verified outputs and runs integration tests

**Rationale:** The framework's own quality gates (pre-registration, information barriers, independent verification, evidence-based pass/fail gates) provide robust quality control. `acceptEdits` auto-approves Edit/Write on project files — the exact surface pipeline agents need — while leaving Bash under the normal classifier. Observed on Claude Code 2.1.112: `mode: "auto"` denied project-file Edit/Write for team-spawned subagents (see audit log), and `mode: "bypassPermissions"` was not honored for tmux-backed team agents.

### Blocking Behavior

**The Agent tool is blocking** — it returns only when the subagent completes. Do not poll, sleep, or manually check `$RND_DIR` files for progress. Spawn agents and process their results when the tool returns.

- **Never** use `sleep` to wait for subagents
- **Never** write bash loops to check if build artifacts exist yet
- **Never** scan `$RND_DIR/builds/` to see if a builder is done — the Agent tool tells you
- **Do** spawn multiple agents in parallel (multiple Agent tool calls in one message) for independent tasks within a wave
- **Do** use `run_in_background: true` on Agent calls if you want to continue working while agents run, then process results when notified

## Execution Phases

1. **Plan** — Run environment discovery (structured checklist scan for package manager, test framework, CI, external services, env vars, secrets). Decompose the task, write pre-registrations with `fulfills` traceability, build dependency matrix. Generate Validation Contract (numbered VAL-AREA-NNN assertions with exact evidence commands). Produce enriched plan.md with sections: Task Tree, Environment Setup, Infrastructure, Testing Strategy, Worker Guidelines, Validation Contract, Pre-Registration Documents, Dependency Matrix, Execution Schedule, Iteration Budgets. Write exploration cache to `$RND_DIR/exploration/`. In multi-agent mode, the Planner agent handles this phase.
2. **Schedule** — Create execution waves from dependency matrix. In multi-agent mode, the Orchestrator session handles scheduling directly.
3. **Build** — Work tasks in parallel within waves. Produce code + tests + self-assessment. Builder agents are spawned per task.
3.5. **Proof Gate** (advisory) — Attempt Lean 4 formal proofs for each task's pre-registered criteria. Results (PROVEN/UNPROVEN) are passed to the Verifier as supplementary evidence. Pipeline continues regardless of proof outcomes. Skipped when Lean is unavailable. In multi-agent mode, Proof-Gate agents handle this phase.
3.75. **Reality Audit** (blocking) — Run on every task. Adversarially verify every external reference in the task's implementation: APIs, schemas, env vars, SDK behavior, file contracts. The Planner's declared external dependencies are audit targets, but the auditor must also discover undeclared external references in the code. INVALID_FOUND routes the task back to build with "expected X, found Y" feedback before verification proceeds. VALIDATED_ALL, VALIDATED_PARTIAL, and SKIPPED proceed to verification. In multi-agent mode, Reality-Auditor agents handle this phase.
4. **Verify** — Check each task against pre-registered criteria. PASS/FAIL/ITERATE. In multi-agent mode, Verifier agents are spawned independently.
5. **Iterate** — On FAIL, build phase gets feedback only (not fixes). Max 3 cycles, then escalate.
6. **Integrate** — Merge verified outputs, run integration tests, system validation. In multi-agent mode, the Integrator agent handles this phase.

## Gate Criteria

**Gate 1 (post-plan):** Every task has complete pre-registration with testable criteria, `fulfills` field linking to VAL assertions, and all Validation Contract assertions are covered.
**Gate 2 (post-build):** Code + tests + artifacts submitted. Tests pass locally.
**Gate 2.5 (post-reality-audit):** Reality Audit complete for every task in the wave. Any INVALID verdict blocks pipeline progression for that task — it must return to build before proceeding to verification.
**Gate 3 (post-verify):** Verification PASS on all criteria with evidence.
**Gate 4 (post-integrate):** Integration tests pass. No regressions. System validation passes.

## Task Status Determination

Task status is derived from artifact files — no separate state file is needed. At each gate, check:

| Artifact exists? | Status |
|-----------------|--------|
| `$RND_DIR/integration/wave-<N>-report.md` contains SHIP | integrated |
| `$RND_DIR/verifications/T<id>-verification.md` contains PASS | verified |
| `$RND_DIR/verifications/T<id>-verification.md` contains NEEDS ITERATION | iterating |
| `$RND_DIR/builds/T<id>-manifest.md` exists and is non-empty | built |
| Task in plan.md but no build artifact | planned |

**At each gate**, validate the expected artifact exists and is non-empty (use Bash `test -s`). If missing, report to the user via `AskUserQuestion` and do not proceed with that task.

**Always use pipeline IDs in user-facing output.** When displaying task references, blocked-by relationships, or status updates, always use `T<n>` pipeline IDs — never raw Claude Code internal IDs (`#<n>`). Resolve internal IDs by matching against `metadata.pipelineId` set during `TaskCreate`, or by extracting the `T<n>` prefix from the task subject.

**Before scheduling each wave**, scan `$RND_DIR/builds/` and `$RND_DIR/verifications/` to determine which tasks are complete. Skip tasks that already have the expected artifacts for the current phase.

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

- **Small tasks (<1hr):** Collapse — one Builder + one Verifier (single judge). Lightweight pre-registration.
- **Medium tasks:** Full framework with parallel waves. Use 2-judge consensus verification per task.
- **Large tasks (multi-day):** Add design review gate between Plan and Schedule. Add sub-waves. Use 2-judge consensus verification.
- **Exploratory:** Add Phase 0 — spike 2-3 approaches with time-box before committing.
- **High-stakes:** Multi-judge verification (2 judges + tiebreaker on disagreement). Add formal invariants via Proof Gate.

