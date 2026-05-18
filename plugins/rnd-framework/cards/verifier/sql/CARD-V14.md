---
id: V14
role: verifier
language: sql
tags: [critique-evidence, fail-case, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: SELECT COUNT(*) performs a full sequential scan in PostgreSQL — verify performance under load
specializes: [P-EFFECTS-EDGE-01]
---

**Good verification comment:**
> NEEDS ITERATION. `SELECT COUNT(*) FROM events WHERE user_id = $1` is called on every page load. On a table with 10M rows, this is a sequential scan of the filtered subset — no index can satisfy COUNT(*) without visiting every matching tuple (MVCC overhead). `EXPLAIN ANALYZE` on a production-sized dataset shows 340ms per call. The success criterion requires p99 < 50ms. Either use an approximate count (`SELECT reltuples FROM pg_class WHERE relname = 'events'`), a materialized counter, or a covering index that allows index-only scans. Present benchmark evidence with realistic row counts.

**Worse verification comment:**
> The COUNT query returns the correct number of rows. The test passes.

**Why good is better:** Correctness and performance are separate criteria. A COUNT that returns the right answer in 340ms is correct and slow. PostgreSQL's MVCC model means COUNT(*) must read every qualifying row to determine which are visible to the current transaction — it cannot use a B-tree to shortcut this. The worse comment passes a query that will become a latency cliff at scale. Performance criteria require benchmark evidence, not a passing unit test.
