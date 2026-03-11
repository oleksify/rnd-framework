---
name: rnd-scaling
description: "Use when deciding how much R&D pipeline ceremony a task needs — scales from trivial (quick mode) to high-stakes (dual verification)"
---

# R&D Scaling

## Overview

The R&D pipeline scales to task complexity. A typo fix doesn't need four agents and three gates. A security-critical feature does.

**Core principle:** Always use the pipeline. Scale it, don't skip it.

## Scaling Tiers

### Trivial (fix typo, add log line)

**Entry:** `/rnd-framework:quick`
**Process:**
1. Write a one-line pre-registration (inline, no subagent)
2. Make the change yourself
3. Spawn one `rnd-framework:rnd-verifier` to confirm
4. Done

**Skip:** Planner, dependency scheduling, Integrator
**Keep:** Pre-registration, independent verification

### Small (<1 hour of work)

**Entry:** `/rnd-framework:quick`
**Process:**
1. Write a brief pre-registration (inline)
2. Implement with TDD (use `rnd-framework:rnd-building`)
3. Spawn `rnd-framework:rnd-verifier` for independent verification
4. Max 2 iterations

**Skip:** Planner subagent, dependency scheduling, Integrator
**Keep:** Pre-registration, TDD, independent verification

### Medium (multiple components, 1-4 hours)

**Entry:** `/rnd-framework:start`
**Process:**
1. Spawn `rnd-framework:rnd-planner` for hierarchical decomposition
2. Schedule waves with dependency analysis
3. Spawn Builder(s) per wave
4. Independent verification per task
5. Integration testing per wave

**Full pipeline.** All agents, all gates.

### Large (multi-day, many components)

**Entry:** `/rnd-framework:start`
**Process:**
1. Full pipeline + design review gate between Plan and Schedule
2. Sub-waves within large waves

### High-Stakes (security, financial, data integrity)

**Entry:** `/rnd-framework:start`
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

Could a failure cause security/financial/data harm?
  -> High-stakes tier
```

## Anti-Pattern: Skipping the Pipeline

"This is too simple for the pipeline" is never true. The pipeline scales down to one pre-registration line and one verification check. That takes 30 seconds. Skipping it means unverified work.

## Related Skills

- `rnd-framework:rnd-orchestration` — Full pipeline overview
- `rnd-framework:using-rnd-framework` — Available commands
