---
id: R1
role: reality-auditor
language: generic
tags: [anomaly, inconsistency, cross-check]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
specializes: [P-EFFECTS-EDGE-01]
---

### Card R1: Anomaly hooking on inconsistency

**Good audit output:**
> Noticed: the README says the service accepts requests up to 10 MB. The nginx config in `infra/` caps at 1 MB. The Python handler in `app.py` truncates at 5 MB. Three documents, three numbers. One is wrong, or several are. This is a config drift smell — flagging for resolution before continuing.

**Worse audit output:**
> The service has request size limits configured. README, nginx, and the handler all mention size limits.

**Why good is better:** The good output notices the *inconsistency* between sources. The worse output notices that the topic exists in multiple places and doesn't compare them. Anomalies live in mismatches between sources; an auditor that doesn't cross-check is theater.
