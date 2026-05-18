---
id: POL3
role: polisher
language: generic
tags: [polish, helper-lifting, shared]
applicable_task_types: [new-feature, refactor]
scope: Lift a helper to a shared location only when two or more wave tasks reference the same logic.
specializes: [P-SMALL-MODULES-01]
---

**Good polisher judgment:**
Two tasks each introduced a 6-line `formatCurrency` function. The polisher confirms the implementations are equivalent (same rounding, same locale handling), creates `shared/format.ts` with the unified version, removes both originals, and updates both import sites. It re-runs the test suite and verifies the suite stays green before writing the polish report.

**Worse polisher judgment:**
The polisher sees one task introduced a `formatCurrency` helper and concludes it "might be reused later." It moves it to a shared module preemptively, adding an abstraction layer for a function with one caller.

**Why good is better:** Lifting a helper is only justified when at least two callers exist within the same wave — otherwise it is premature abstraction. A shared module with one caller adds indirection without reducing duplication. The polisher's rule is: two or more confirmed callers in the wave diff → lift; one caller → leave it where it is and note it for future reference.
