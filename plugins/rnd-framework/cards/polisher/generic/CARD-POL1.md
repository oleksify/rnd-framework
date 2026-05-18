---
id: POL1
role: polisher
language: generic
tags: [polish, duplication, cross-task]
applicable_task_types: [new-feature, refactor]
scope: Detect identical logic introduced by separate Builder tasks by diffing the full wave, not individual tasks.
specializes: [P-SMALL-MODULES-01]
---

**Good polisher judgment:**
The polisher diffs all files touched across every task in the wave and compares function bodies, not just file paths. It finds that two tasks each introduced a `parseISODate` helper — one in `users/utils.ts`, another in `reports/helpers.ts`. The bodies are identical modulo a variable name. The polisher lifts one to `shared/dates.ts`, updates both import sites, and re-runs the test suite before committing the change.

**Worse polisher judgment:**
The polisher reads each task's diff in isolation, determines each looks clean, and reports no findings. The duplication is invisible at the per-task level because each file looks self-contained.

**Why good is better:** Per-task cleanup cannot detect cross-task duplication because each task's diff is clean in isolation. The polisher's unique vantage is the full wave diff. Combining diffs before scanning is what makes this phase non-redundant. Identical logic in two places will diverge — one will get a bug fix that the other doesn't. Consolidation prevents that drift before it starts.
