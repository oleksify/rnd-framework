---
id: V13
role: verifier
language: sql
tags: [critique-evidence, fail-case, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Unnamed constraints generate Postgres-derived names that collide across migrations
specializes: [P-IMPOSSIBLE-01]
---

**Good verification comment:**
> FAIL. The migration adds `CHECK (status IN ('active', 'inactive'))` without a `CONSTRAINT` name. Postgres will generate `orders_status_check` — but a prior migration already added a CHECK on `status` and generated the same name. Running this migration on a database where the prior migration ran will fail with `constraint "orders_status_check" of relation "orders" already exists`. The fix is `CONSTRAINT orders_status_check2 CHECK (...)` or, better, a unique descriptive name. Show evidence of the migration running against a database that already has the prior schema.

**Worse verification comment:**
> The CHECK constraint ensures the status field only contains valid values. The constraint looks correct.

**Why good is better:** Postgres auto-generates constraint names from the table and column name. Two migrations that add constraints to the same column generate the same name — and the second migration fails silently in CI (where the DB is always clean) but catastrophically in production (where prior migrations have already run). The worse comment never checks whether the auto-generated name is already taken. Evidence of the migration running against a realistic accumulated schema is the only way to surface this class of bug.
