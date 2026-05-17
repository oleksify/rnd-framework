---
id: R13
role: reality-auditor
language: sql
tags: [anomaly, skepticism, inconsistency]
applicable_task_types: [new-feature, bugfix, refactor]
scope: PostgreSQL default isolation is READ COMMITTED — concurrent writes can cause lost updates
specializes: [P-IMPOSSIBLE-01]
---

### Card R13: READ COMMITTED does not prevent lost updates — specializes the impossible-states principle for PostgreSQL isolation

**Good audit observation:**
> The inventory deduction uses `UPDATE items SET qty = qty - $1 WHERE id = $2 AND qty >= $1`. Under READ COMMITTED (Postgres default), two concurrent transactions can both read `qty = 5`, both pass the `qty >= 1` check, and both execute — leaving `qty = 3` instead of `4`. This is a lost-update anomaly. Use `SELECT ... FOR UPDATE` to lock the row before reading, or restructure as a single conditional update and check `rowsAffected`.

**Worse audit observation:**
> The update checks the current quantity before decrementing. The query looks correct.

**Why good is better:** READ COMMITTED means each statement sees the latest committed row at the time the statement starts — not at the time the transaction started. Two transactions can both snapshot the same row, both pass a guard condition, and both commit, overwriting each other's work. SERIALIZABLE prevents this but costs throughput. The practical fix for lost-update patterns is a pessimistic `SELECT FOR UPDATE` or a conditional update with `rowsAffected` validation — not faith in the default isolation level.
