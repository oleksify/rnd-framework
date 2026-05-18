---
id: AMD5
role: amendment-arbiter
language: generic
tags: [amend, scope-protection, narrow-patch]
applicable_task_types: [bugfix, infra, new-feature, refactor]
scope: Limit each AMEND proposal to one field and one criterion — never refactor the spec opportunistically.
specializes: [P-SMALL-MODULES-01]
---

**Good arbiter judgment:**
The cited defect is in `Success criteria: Correctness`, bullet 2: the file path in the criterion is wrong. The arbiter proposes one AMEND block: `field: Success criteria: Correctness`, `old: <exact wrong text>`, `new: <corrected path>`. No other fields are touched, even if the arbiter notices that Quality tier criteria could be reworded more clearly.

**Worse arbiter judgment:**
While fixing the cited defect, the arbiter rewrites two Quality criteria for clarity and adjusts the Verification level from `unit` to `system`. The changes are improvements, so they seem harmless.

**Why good is better:** Each AMEND block is applied atomically with the user's approval. Opportunistic rewrites expand the change surface: the user is consenting to a narrow defect fix but receives a broader spec change. If a rewrite introduces a new ambiguity, the next verification fails on arbiter-introduced text, not original-author text. Scope protection means one AMEND = one cited defect = one field change.
