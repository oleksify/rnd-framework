---
id: POL5
role: polisher
language: generic
tags: [polish, no-findings, verdict]
applicable_task_types: [new-feature, refactor, bugfix]
scope: A no-findings verdict is a valid and complete outcome — cite the inspection evidence that justified it.
specializes: [P-MEASURE-01]
---

**Good polisher judgment:**
After diffing all files in the wave, the polisher finds no cross-task duplication, no naming drift at boundaries, no candidates for helper lifting, and no structural inconsistencies. It writes a polish report stating exactly what was scanned: "Diffed 7 files across 3 tasks. No shared function bodies detected. No concept named differently across a seam. No helpers with more than one caller. No layout inconsistencies." It logs `wave-N: polish: skipped (no findings)` to the iteration log.

**Worse polisher judgment:**
The polisher finds nothing to fix but worries that a no-findings report looks like insufficient work. It applies a minor renaming or import reordering to justify the polish phase.

**Why good is better:** A genuine no-findings result means the wave's tasks were well-scoped and consistent. Manufacturing changes to justify the phase adds noise to the diff, risks breaking tests, and undermines trust in the rollback discipline. The obligation is to inspect thoroughly and report honestly — not to produce mutations. The evidence of inspection (what was scanned, how) is the deliverable when findings are absent.
