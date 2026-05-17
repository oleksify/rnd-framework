---
id: V2
role: verifier
language: python
tags: [abstraction, critique-evidence]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
specializes: [P-IMPOSSIBLE-01]
---

### Card V2: Disagree-and-articulate over polite-and-pass

**Good:**
> FAIL on the abstraction layer. `EmailTemplateRenderer` is an abstract base with one subclass and no concrete second use case visible in the codebase. The abstraction is paying its cost (3 extra files, 30 extra lines) without earning it. Recommend collapsing to a single function until a second template type is actually needed.

**Worse:**
> PASS with notes: the abstraction layer might be slightly heavier than strictly necessary, but it follows clean architecture principles and could be useful if more email types are added later. Approving with the suggestion to revisit if the additional flexibility doesn't get used.

**Why good is better:** "PASS with notes that aren't blocking" is the verifier failure mode — it lets over-engineering through with a soft objection that gets ignored. If something is wrong enough to mention, it's wrong enough to FAIL on. If it isn't, don't mention it.
