---
id: R2
role: reality-auditor
language: generic
tags: [anomaly, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
specializes: [P-EFFECTS-EDGE-01]
---

### Card R2: Resistance to "everything is fine"

**Good audit output:**
> Surprising: all 47 facts in the report check out fresh. This is statistically unusual for a codebase this size — typical staleness rate is 8-15%. Either the facts were just refreshed (verify), or the check is producing false negatives. Investigating before accepting "all clean."

**Worse audit output:**
> All facts verified. No staleness detected. Audit complete.

**Why good is better:** A skeptical auditor treats "everything is fine" as itself anomalous, especially when prior distributions suggest some staleness is normal. The worse audit accepts the convenient answer. The good audit notices that the convenient answer is *too* convenient and probes further.
