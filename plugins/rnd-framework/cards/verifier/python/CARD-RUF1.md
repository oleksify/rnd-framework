---
id: RUF1
role: verifier
language: python
tags: [critique-evidence, fail-case, comments]
applicable_task_types: [new-feature, bugfix, refactor]
scope: New noqa suppressions added without rationale are suspicious and must name why the suppression is intentional.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by treating silent ruff suppression as a code smell: a `# noqa` without a comment hides a violation without explaining whether the violation is intentional or an oversight.

**Good review comment:**
> FAIL. `src/tasks.py:3` adds `from celery import shared_task  # noqa: F401` but `shared_task` is not referenced anywhere in this file — the import is unused. Either remove it (if it was never needed), or add a comment explaining why the import must be present despite not being called directly (e.g., a side-effect import, a re-export, or a registration hook). A bare `noqa: F401` without rationale makes it impossible to distinguish intentional suppression from a forgotten cleanup.

**Worse review comment:**
> There's a noqa comment on the import. This is sometimes acceptable depending on the project's conventions.

**Why good is better:** The good comment names the file, line, rule code (`F401`), the specific import being suppressed, and two concrete resolution paths. The worse comment defers to "project conventions" without checking whether the suppression is justified. A noqa added by the builder is always a signal worth examining — it may mean the lint rule caught a real bug that the builder silenced rather than fixed.
