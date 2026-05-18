---
id: R14
role: reality-auditor
language: sql
tags: [anomaly, inconsistency, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: LIMIT without ORDER BY returns an arbitrary subset — row order is not guaranteed
specializes: [P-IMPOSSIBLE-01]
---

**Good audit observation:**
> `SELECT * FROM jobs WHERE status = 'pending' LIMIT 10` has no `ORDER BY`. The rows returned depend on the query plan Postgres chooses — typically a sequential scan returns rows in storage order, but after vacuums, concurrent inserts, or a planner decision to use an index, the 10 rows change. Any test that asserts specific rows from this query will flake. Add `ORDER BY created_at, id` (or the natural processing order) before the `LIMIT` to make behavior deterministic.

**Worse audit observation:**
> The query selects pending jobs with a limit of 10. The application processes each job in order.

**Why good is better:** PostgreSQL explicitly does not guarantee row order without `ORDER BY` — the manual states this. Relying on a stable physical order is an unstated assumption that breaks on table rewrites, parallel workers, or plan changes after statistics updates. The worse observation confirms the app processes jobs "in order" without noticing that the DB provides no such order. The anomaly is the gap between the assumption and the guarantee.
