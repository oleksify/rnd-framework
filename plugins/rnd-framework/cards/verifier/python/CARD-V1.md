---
id: V1
role: verifier
language: python
tags: [critique-evidence, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
---

### Card V1: Critique with evidence, not vibes

**Good review comment:**
> FAIL. `parse_timestamp` returns `None` on parse failure but `process_event` (line 47) dereferences the return value without a None-check. This will `AttributeError` on any malformed timestamp. Either make `parse_timestamp` raise, or handle None at the call site.

**Worse review comment:**
> This error handling feels a bit fragile and might cause issues downstream. Consider making it more robust.

**Why good is better:** The good comment names the bug, the line, the consequence, and two ways to fix it. The worse comment names a feeling and asks for "robustness," which the builder will pattern-match to "add more try/except." Vague critique produces vague fixes; specific critique produces specific fixes.
