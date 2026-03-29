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

The framework defines 8 specialized agent roles. In single-flow mode, the session plays all roles sequentially. In multi-agent mode, dedicated agents are spawned for each role.

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
  - [ ] Specific, testable condition 1
  - [ ] Specific, testable condition 2
Verification level: unit | integration | system
Dependencies: [list of task IDs]
External dependencies:
  - system: [DB | API | file | env | service]
    contract: [What is assumed about this system — schema, response shape, format, presence]
    verification: [How this will be confirmed — e.g., Read actual schema, query endpoint, inspect file sample]
```

## Execution Modes

The framework supports two execution modes. Use `/rnd-framework:rnd-start` to select.

### Single-Flow Mode

All pipeline phases run sequentially in one session. No agents are spawned. The session model handles all phases — planning, building, verification, and integration. Best for small-to-medium tasks or when agent spawning is unavailable.

Skills provide phase-specific discipline:
- Planning: `rnd-framework:rnd-decomposition`
- Building: `rnd-framework:rnd-building`
- Verification: `rnd-framework:rnd-verification`
- Integration: `rnd-framework:rnd-integration`

### Multi-Agent Mode

Dedicated agents are spawned for each pipeline role. The orchestrator session coordinates them, enforcing information barriers and gate criteria. Best for medium-to-large tasks requiring rigorous separation of concerns.

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

All pipeline agents are spawned with `mode: "bypassPermissions"`:

- **Planner** — decomposes tasks and writes pre-registrations
- **Builder** — implements tasks with TDD discipline
- **Verifier** — independently checks outputs against pre-registered criteria
- **Integrator** — merges verified outputs and runs integration tests

**Rationale:** The framework's own quality gates (pre-registration, information barriers, independent verification, evidence-based pass/fail gates) provide robust quality control. OS-level permission prompts are redundant and disruptive to autonomous pipeline operation.

### Blocking Behavior

**The Agent tool is blocking** — it returns only when the subagent completes. Do not poll, sleep, or manually check `$RND_DIR` files for progress. Spawn agents and process their results when the tool returns.

- **Never** use `sleep` to wait for subagents
- **Never** write bash loops to check if build artifacts exist yet
- **Never** scan `$RND_DIR/builds/` to see if a builder is done — the Agent tool tells you
- **Do** spawn multiple agents in parallel (multiple Agent tool calls in one message) for independent tasks within a wave
- **Do** use `run_in_background: true` on Agent calls if you want to continue working while agents run, then process results when notified

## Execution Phases

1. **Plan** — Decompose the task, write pre-registrations, build dependency matrix. Write structured exploration findings to `$RND_DIR/exploration/` (one markdown file per area explored) so downstream phases can read cached context instead of re-exploring the codebase. In multi-agent mode, the Planner agent handles this phase.
2. **Schedule** — Create execution waves from dependency matrix. In multi-agent mode, the Orchestrator session handles scheduling directly.
3. **Build** — Work tasks (parallel within waves in multi-agent mode, sequential in single-flow). Produce code + tests + self-assessment. In multi-agent mode, Builder agents are spawned per task.
3.5. **Proof Gate** (advisory) — Attempt Lean 4 formal proofs for each task's pre-registered criteria. Results (PROVEN/UNPROVEN) are passed to the Verifier as supplementary evidence. Pipeline continues regardless of proof outcomes. Skipped when Lean is unavailable. In multi-agent mode, Proof-Gate agents handle this phase.
3.75. **Reality Audit** (blocking) — Adversarially test each task's external service contracts. INVALID_FOUND routes the task back to build with "expected X, found Y" feedback before verification proceeds. VALIDATED_ALL, VALIDATED_PARTIAL, and SKIPPED proceed to verification. In multi-agent mode, Reality-Auditor agents handle this phase.
4. **Verify** — Check each task against pre-registered criteria. PASS/FAIL/ITERATE. In multi-agent mode, Verifier agents are spawned independently.
5. **Iterate** — On FAIL, build phase gets feedback only (not fixes). Max 3 cycles, then escalate.
6. **Integrate** — Merge verified outputs, run integration tests, system validation. In multi-agent mode, the Integrator agent handles this phase.

## Gate Criteria

**Gate 1 (post-plan):** Every task has complete pre-registration with testable criteria.
**Gate 2 (post-build):** Code + tests + artifacts submitted. Tests pass locally.
**Gate 3 (post-verify):** Verification PASS on all criteria with evidence.
**Gate 4 (post-integrate):** Integration tests pass. No regressions. System validation passes.

## User Decision Points

When a phase completes and the user needs to decide what happens next, **use `AskUserQuestion`/`AskUser` with structured options** instead of open-ended text like "Would you like me to...?". This eliminates decision fatigue.

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

- **Small tasks (<1hr) / quick mode:** Collapse — one Builder + one Verifier (single judge). Lightweight pre-registration. Use single-flow mode.
- **Medium tasks:** Full framework with parallel waves. Use 2-judge consensus verification per task. Single-flow or multi-agent mode.
- **Large tasks (multi-day):** Add design review gate between Plan and Schedule. Add sub-waves. Use 2-judge consensus verification. Multi-agent mode recommended.
- **Exploratory:** Add Phase 0 — spike 2-3 approaches with time-box before committing.
- **High-stakes:** Multi-judge verification (2 judges + tiebreaker on disagreement). Add formal invariants via Proof Gate. Multi-agent mode required.

## Mission Mode

The framework integrates with **Factory Droid Missions** as an optional orchestration layer. When running inside a Factory Droid Mission:

- The Mission orchestrator handles high-level feature decomposition and worker assignment
- Each worker session can use rnd-framework skills for discipline (pre-registration, TDD, verification checklists)
- The information barrier is maintained within each worker's session via `read-gate.sh`
- Mission validation contracts serve a similar role to pre-registration success criteria — define testable conditions before implementation

**How rnd-framework discipline enhances Mission workflows:**
- **Pre-registration** — Workers write success criteria before coding, reducing scope creep
- **TDD via `rnd-building`** — Red-green-refactor discipline within each worker session
- **Verification checklists** — Workers self-verify against criteria before calling `EndFeatureRun`
- **Convergent iteration** — When validation fails, workers address all failures in a single pass

Mission mode does not replace the multi-agent pipeline — it operates at a higher level. A Mission worker can invoke `/rnd-framework:rnd-quick` for lightweight tasks or use the full pipeline via `/rnd-framework:rnd-start` for complex features within their assigned scope.
