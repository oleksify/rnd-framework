---
name: rnd-roadmapping
description: "Use when planning multi-session work or managing roadmap milestones — defines roadmap.md format, milestone lifecycle, and how to update progress after SHIP"
effort: low
user-invocable: false
---

# R&D Roadmapping

## Overview

For work that spans multiple sessions, a roadmap tracks progress across pipeline runs. Each milestone is one session's worth of deliverable work.

**Core principle:** Each milestone must be independently valuable. If you stop after M2, M1 and M2 should still be useful — not half-finished infrastructure.

## When to Use

- Before starting multi-session work with a Planner
- When updating milestone status after a SHIP verdict
- When parking mid-session work and planning resumption

## roadmap.md Format

```markdown
# Roadmap: [Broad Task Title]

Created: YYYY-MM-DD
Last updated: YYYY-MM-DD

## Goal
[1-3 sentences describing the overall multi-day objective]

## Milestones

### M1: [Title] [STATUS]
**Description:** [What this milestone delivers — 1-3 sentences, enough for a /start session]
**Session:** [session ID, filled after milestone starts]
**Delivered:** [Summary of what was built, filled after DONE]

### M2: [Title] [STATUS]
**Description:** ...
**Session:** ...
**Delivered:** ...
```

## Milestone Statuses

Exactly four statuses: `NOT_STARTED`, `IN_PROGRESS`, `DONE`, `SKIPPED`

- `NOT_STARTED` → `IN_PROGRESS`: a session starts for this milestone
- `IN_PROGRESS` → `DONE`: SHIP verdict — record session ID + deliverables
- `IN_PROGRESS` → `SKIPPED`: user decides to skip (record reason inline)
- `NOT_STARTED` → `SKIPPED`: user decides to skip before starting

## Where roadmap.md Lives

Store at the project base dir — output of `rnd-dir.sh --base` — not inside a session dir. This makes it persistent across pipeline runs.

```bash
ROADMAP="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --base)/roadmap.md"
```

## Planner: Decomposing into Milestones

When a Planner receives a multi-session goal, decompose it into milestones — not tasks:

- Milestones are broad deliverables (roughly one session each), not individual tasks
- 3-7 milestones is the right range; fewer than 3 is likely one session; more than 7 is under-decomposed
- Each **Description** must be self-contained enough to paste into `/rnd-framework:rnd-start`
- Note dependencies inline but keep them minimal — "M3 requires M2's API contract" is fine; a web of cross-dependencies is a decomposition smell
- The Planner creates individual tasks within each session; milestones are session-level units

## Milestone Execution and Verification

Each milestone goes through the full pipeline independently: **Plan → Build → Verify → Integrate**. Verification is not optional, even for milestones that appear simple. The multi-judge verification in Phase 3 is the framework's core quality guarantee — skipping it means unverified work ships.

When executing a milestone:
- The milestone description becomes the task for `/rnd-framework:rnd-start`
- The pipeline runs all phases including independent multi-judge verification
- A SHIP verdict from the Integrator marks the milestone as DONE
- If already inside a `/rnd-framework:rnd-start` session (e.g., Phase 0 created the roadmap), the milestone description flows to Phase 1 (Plan) — do not recursively re-invoke start

**Anti-pattern:** Completing milestone work inline without spawning the pipeline phases. Even small milestones (documentation, config changes) need at least single-judge verification per the scaling skill's criticality tiers.

## Updating Progress After SHIP

After a SHIP verdict, update roadmap.md:

1. Read `roadmap.md` from the project base dir (`rnd-dir.sh --base`)
2. Find the `IN_PROGRESS` milestone
3. Change its status to `DONE`
4. Fill in **Session** (the session ID from `$RND_DIR`) and **Delivered** (summary of what shipped)
5. Update `Last updated` to today's date

## Parking Work Mid-Session

If stopping before SHIP, update the `IN_PROGRESS` milestone with a progress note — do NOT change status to `DONE`:

```markdown
### M2: [Title] IN_PROGRESS
**Description:** ...
**Session:** [session ID]
**Progress:** [what's been built so far]
**Remaining:** [what's left to reach SHIP]
```

The milestone stays `IN_PROGRESS` until a SHIP verdict is received.

## Related Skills

- `rnd-framework:rnd-orchestration` — Full pipeline overview
- `rnd-framework:rnd-completion` — Post-SHIP workflow (branch, PR, cleanup)
- `rnd-framework:rnd-decomposition` — Task-level decomposition within a session
