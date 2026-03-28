---
name: rnd-scheduling
description: "Use when planning execution waves from a dependency matrix — dependency-based scheduling and wave coordination"
user-invocable: false
effort: medium
---

# R&D Scheduling

## Overview

Use dependency analysis to schedule tasks into parallel execution waves. Tasks within a wave have no cross-dependencies and can run concurrently.

**Core principle:** Organize independent tasks into waves for sequential execution within each wave.

## When to Use

- After decomposition produces a dependency matrix
- When coordinating multiple build tasks
- When coordinating multiple verification tasks
- Phase 2 (Schedule) of the R&D pipeline

## Wave Construction

### From Dependency Matrix to Waves

1. **Wave 1:** Tasks with zero dependencies
2. **Wave 2:** Tasks depending only on Wave 1 tasks
3. **Wave N:** Tasks depending only on tasks in Waves 1 through N-1
4. **Circular dependencies:** Flag for re-decomposition — these are planning errors

### Sequential Execution Within Waves

Within each wave:
- Build each task sequentially (invoke `rnd-framework:rnd-building` skill)
- After ALL tasks in the wave are built, verify each sequentially (invoke `rnd-framework:rnd-verification` skill)

### Task Scope

Each task gets:
- **Specific scope:** One task with its pre-registration
- **Clear goal:** Implement/verify against success criteria
- **Constraints:** Don't modify code outside your task scope
- **Expected output:** Manifest + self-assessment (build) or verification report (verify)

## Wave Execution Order

```
Wave 1: [T1, T2, T3] -> Build all -> Verify all -> Integrate
Wave 2: [T4, T5]     -> Build all -> Verify all -> Integrate
Wave 3: [T6]          -> Build -> Verify -> Final integration
```

## When NOT to Parallelize

- Tasks that edit the same files — sequential within wave
- Tasks with shared state or resources
- Exploratory work where you don't know what's broken yet
- When a prior wave's integration revealed issues

## Related Skills

- `rnd-framework:rnd-decomposition` — Produces the dependency matrix
- `rnd-framework:rnd-orchestration` — Pipeline overview
