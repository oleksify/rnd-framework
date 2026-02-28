---
name: rnd-isolation
description: "Use when Builder agents need workspace isolation — git worktrees for parallel builders working on the same codebase without conflicts"
---

# R&D Isolation

## Overview

When multiple Builder agents work in parallel (within a wave), they may need isolated copies of the codebase to avoid file conflicts. Git worktrees provide this isolation.

**Core principle:** Parallel builders should not step on each other's files.

## When to Use

- Multiple Builder agents working in the same wave
- Tasks that modify overlapping files (rare if decomposition is good)
- Large tasks where builder isolation reduces merge conflicts
- When `rnd-framework:rnd-scaling` recommends isolation (Large or High-stakes tiers)

## When NOT to Use

- Single builder (no conflict possible)
- Tasks that create new files only (no overlap)
- Quick mode (single builder + verifier)

## Process

### 1. Create Worktree Per Builder

Before dispatching builders for a wave:

```bash
git worktree add .rnd/worktrees/T<id> -b rnd/T<id>
```

### 2. Builder Works in Worktree

Each builder operates in its own worktree directory. All file paths are relative to the worktree root.

### 3. Merge After Verification

After all tasks in the wave pass verification:
- The Integrator merges each worktree branch back
- Resolve any conflicts
- Run integration tests on the merged result

### 4. Clean Up Worktrees

```bash
git worktree remove .rnd/worktrees/T<id>
git branch -d rnd/T<id>
```

## Related Skills

- `rnd-framework:rnd-scheduling` — Wave execution and parallel dispatch
- `rnd-framework:rnd-building` — Builder methodology
- `rnd-framework:rnd-integration` — Merging verified outputs
