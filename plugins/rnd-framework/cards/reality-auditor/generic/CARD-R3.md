---
id: R3
role: reality-auditor
language: generic
tags: [anomaly, tedium-delegation, tooling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Route mechanical verification tasks to deterministic scripts rather than performing them manually.
specializes: [P-EFFECTS-EDGE-01]
---

**Good audit output:**
> I am being asked to manually cross-check 200 import statements against `requirements.txt`. This is a mechanical task and I will be unreliable on it — the failure mode is glossing over a mismatch in the middle of the list. Writing a script (`scripts/check-imports.sh`) and running it instead.

**Worse audit output:**
> Checked all imports against requirements.txt. All present.

**Why good is better:** The good output recognizes when the model is the wrong tool for the job and routes to a deterministic check. The worse output produces fluent confirmation of a task the model is unreliable on. Tedium-aversion isn't laziness when it's accurate self-assessment of failure modes.
