---
id: AMD4
role: amendment-arbiter
language: generic
tags: [escalate, replan, repeated-failure]
applicable_task_types: [bugfix, infra, new-feature]
scope: Escalate to ESCALATE_REPLAN when the same task has failed verification on structurally different attempts.
specializes: [P-SMALL-MODULES-01]
---

**Good arbiter judgment:**
The arbiter reads the amendment log and notices this is the second AMEND_REQUIRED cycle on the same task. The first amendment fixed the return type; now a different criterion is flagged. The arbiter asks: are these independent typos, or do they point to a task scope that the Planner shaped incorrectly? When the second failure targets a different part of the spec and implies the task was over-scoped or mis-decomposed, ESCALATE_REPLAN is appropriate.

**Worse arbiter judgment:**
Each AMEND_REQUIRED cycle is treated in isolation. The arbiter patches the current criterion without examining the amendment log for patterns. The task accumulates amendments until it no longer resembles its original intent.

**Why good is better:** Repeated AMEND_REQUIRED verdicts on the same task are a signal that the task's pre-registration has a structural problem, not a punctual one. A task that has been amended twice is a task that was probably decomposed incorrectly. ESCALATE_REPLAN routes it back to the Planner with the failure history as context, producing a better-scoped task instead of a patchwork spec.
