---
id: V12
role: verifier
language: sql
tags: [critique-evidence, fail-case, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Migration up and down must both succeed; verify both directions, not just the up path
specializes: [P-IMPOSSIBLE-01]
---

### Card V12: Migrations require both directions to be tested — specializes the impossible-states principle for SQL migrations

**Good verification comment:**
> FAIL. The migration adds a `NOT NULL` column `confirmed_at` with no `DEFAULT`. The `up` migration will fail on any table with existing rows unless a default is supplied during the migration (e.g., `SET DEFAULT now()` then `DROP DEFAULT`). The `down` migration drops the column — which is safe, but it was never run. Test evidence must show both `migrate up` and `migrate down` succeeded against a non-empty table. Present output from both runs.

**Worse verification comment:**
> The migration looks correct. It adds the `confirmed_at` column and the down migration removes it.

**Why good is better:** A migration that reads correctly can still fail at runtime on non-empty tables, on databases with existing constraints, or when run in the reverse direction. The worse comment judges the migration by reading it — not by running it. A PASS requires evidence of both directions succeeding in a realistic environment; "looks correct" is not evidence.
