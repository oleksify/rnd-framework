---
id: R12
role: reality-auditor
language: sql
tags: [anomaly, cross-check, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: EXPLAIN ANALYZE returns actual execution stats — estimates and actuals often diverge
specializes: [P-EFFECTS-EDGE-01]
---

**Good audit observation:**
> `EXPLAIN ANALYZE` shows `rows=1 (estimated)` vs `rows=84231 (actual)` on the nested loop join. The planner believed the `status = 'active'` filter was highly selective, but statistics are stale. An `ANALYZE` on the table or a fresh `VACUUM ANALYZE` would update the row estimate — and the planner would likely switch to a hash join that is orders of magnitude faster. The performance regression is a statistics drift, not a query bug.

**Worse audit observation:**
> The query plan shows a nested loop join. The table has indexes on the relevant columns.

**Why good is better:** `EXPLAIN` alone shows the planner's estimates — it does not execute the query. `EXPLAIN ANALYZE` executes the query and shows both estimates and actuals. A large divergence between the two is itself a finding: it means the planner is flying blind and may be picking a catastrophically wrong join strategy. Always run `EXPLAIN ANALYZE`, never `EXPLAIN` alone, and compare `rows=N (estimated)` vs `rows=M (actual)` as the primary diagnostic signal.
