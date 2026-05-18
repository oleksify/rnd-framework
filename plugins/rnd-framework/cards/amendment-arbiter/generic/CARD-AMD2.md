---
id: AMD2
role: amendment-arbiter
language: generic
tags: [amend, spec-defect, taxonomy]
applicable_task_types: [bugfix, infra, new-feature, refactor]
scope: Classify the spec defect type before deciding between AMEND, REBUILD, or ESCALATE_REPLAN.
specializes: [P-EFFECTS-EDGE-01]
---

**Good arbiter judgment:**
The arbiter identifies the defect type before deciding: a **typo** in a file path (narrow, fix in place → AMEND); a **contradiction** between two criteria (structural, may change behavior → REBUILD); an **under-specified** term where the meaning is genuinely ambiguous (depends on scope impact); a **wrong assumption** about an upstream API that no longer exists (scope-shape wrong → ESCALATE_REPLAN). Knowing the defect type constrains which outcome is even possible.

**Worse arbiter judgment:**
The arbiter treats every spec defect the same way: propose an AMEND and let the user sort it out. A contradiction gets patched with additive language; a wrong assumption gets smoothed over with a footnote.

**Why good is better:** The four defect types have different scopes of impact. Typos are surgical. Contradictions imply the criteria cannot both be satisfied, so the implementation choice was forced — AMEND patches one criterion but leaves the other inconsistent, making REBUILD cleaner. Wrong assumptions about external systems may invalidate the task's decomposition entirely, warranting ESCALATE_REPLAN. Classifying first prevents the wrong outcome from looking plausible.
