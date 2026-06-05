---
name: rnd-scaling
description: "Use when deciding how much R&D pipeline ceremony a task needs — scales from trivial to high-stakes (dual verification)"
user-invocable: false
effort: medium
---

# R&D Scaling

## Overview

The R&D pipeline scales to task complexity. A typo fix doesn't need the full pipeline ceremony. A security-critical feature does.

**Core principle:** Always use the pipeline. Scale it, don't skip it.

## Scaling Tiers

### Trivial (fix typo, add log line)

**Entry:** `/rnd-framework:rnd-start`
**Process:**
1. Write a one-line pre-registration inline
2. Spawn a Builder agent for the change
3. Spawn a Verifier agent to check against criteria
4. Done

**Skip:** Planner, dependency scheduling, Integrator
**Keep:** Pre-registration, verification

### Small (<1 hour of work)

**Entry:** `/rnd-framework:rnd-start`
**Process:**
1. Write a brief pre-registration inline
2. Spawn a Builder agent with TDD (uses `rnd-framework:rnd-building`)
3. Spawn a Verifier agent for independent verification
4. Max 2 iterations

**Skip:** Planner subagent, dependency scheduling, Integrator
**Keep:** Pre-registration, TDD, independent verification

### Medium (multiple components, 1-4 hours)

**Entry:** `/rnd-framework:rnd-start`
**Process:**
1. Spawn `rnd-framework:rnd-planner` for hierarchical decomposition
2. Schedule waves with dependency analysis
3. Spawn Builder(s) per wave
4. Independent verification per task
5. Integration testing per wave

**Full pipeline.** All agents, all gates.

### Large (multi-day, many components)

**Entry:** `/rnd-framework:rnd-start`
**Process:**
1. Full pipeline + design review gate between Plan and Schedule
2. Sub-waves within large waves
3. Proof Gate skipped unless explicitly requested (rarely needed)
4. Reality Audit only for tasks with external dependencies

### Multi-session (multiple days, independent deliverables)

**Entry:** `/rnd-framework:rnd-roadmap`
**Process:**
1. Decompose the broad goal into milestones via the Planner in roadmap mode
2. Each milestone = one pipeline session via `/rnd-framework:rnd-start`
3. After each session's SHIP verdict, update roadmap.md and start the next milestone

**Verification:** Per-session — each milestone goes through the full pipeline independently

### High-Stakes (security, financial, data integrity)

**Entry:** `/rnd-framework:rnd-start`
**Process:**
1. Full pipeline
2. Dual independent verification (two separate Verifiers)
3. Adversarial verification: one Verifier specifically tries to break it
4. Extended iteration budget (5 cycles instead of 3)

## Decision Flow

```
Is the task a single-line change?
  -> Trivial tier

Can it be done in under an hour with clear criteria?
  -> Small tier

Does it involve multiple components or files?
  -> Medium tier

Will it take more than a day?
  -> Large tier

Will it span multiple sessions/days with independent deliverables?
  -> Multi-session tier

Could a failure cause security/financial/data harm?
  -> High-stakes tier
```

## Verification Depth by Criticality

Orthogonal to task size, **criticality** determines how much verification effort each task receives. The Planner should annotate each task in the pre-registration with a criticality tier. The orchestrator reads this annotation to decide verification depth.

### LOW criticality
**Examples:** Config changes, documentation updates, style fixes, renaming, adding log lines.
**Verification:** Single-judge verification. No Proof Gate. Quality tier is advisory-only.
**Rationale:** False negatives here are cheap to fix. Over-verifying wastes tokens.

### NORMAL criticality (default)
**Examples:** Standard features, bug fixes, refactors with clear scope.
**Verification:** Single-judge verification. Standard iteration budget (3).
**Rationale:** Most tasks live here. One independent judge catches the overwhelming majority of issues at a fraction of the token cost.

### HIGH criticality
**Examples:** Security-sensitive code, data migrations, authentication changes, financial calculations, architectural decisions that constrain future work.
**Verification:** Single-judge by default. 2-judge consensus available via explicit opt-in (see below). Extended iteration budget (5). If Lean is available, invoke Proof Gate.
**Rationale:** Sonnet at high effort provides sufficient verification for most high-stakes tasks. Multi-judge available when user explicitly requests maximum confidence.

### How the Planner annotates criticality

In the pre-registration document, add a `Criticality:` field:

```
Task ID: T3
Intent: Add rate limiting to API endpoints
Criticality: HIGH
```

If the Planner omits the field, the orchestrator defaults to NORMAL.

### How the orchestrator applies it

| Criticality | Judges | Iteration budget | Proof Gate |
|-------------|--------|-----------------|------------|
| LOW | 1 | 2 | Skip |
| NORMAL | 1 | 3 | If available |
| HIGH | 1 | 5 | If available |

### Agent Model/Effort Routing by Criticality

Criticality drives both iteration budget (table above) and per-agent model selection. The authoritative source is `rnd-framework:rnd-orchestration` under "Dispatch Policy". The matrix below mirrors it for quick reference:

| Agent | LOW | NORMAL | HIGH | Adaptive? |
|---|---|---|---|---|
| `rnd-planner` | opus/high | opus/high | opus/xhigh | yes |
| `rnd-verifier` | sonnet/high | opus/high | opus/xhigh | yes |
| `rnd-builder` | sonnet/high | sonnet/high | opus/high | yes |
| `rnd-debugger` | sonnet/high | sonnet/high | opus/high | yes |
| `rnd-polisher` | opus/high | opus/high | opus/xhigh | no (per-wave, fixed) |

Key rules:
- `rnd-planner` and `rnd-verifier` escalate to opus at NORMAL and above; `rnd-builder` and `rnd-debugger` escalate only at HIGH.
- `rnd-polisher` is non-adaptive — it always runs at opus regardless of task criticality.
- Effort is NOT per-spawn overridable; it stays at the agent's frontmatter value.

## Anti-Pattern: Skipping the Pipeline

"This is too simple for the pipeline" is never true. The pipeline scales down to one pre-registration line and one verification check. That takes 30 seconds. Skipping it means unverified work.

## Related Skills

- `rnd-framework:rnd-orchestration` — Full pipeline overview
- `rnd-framework:rnd-using-rnd-framework` — Available commands
