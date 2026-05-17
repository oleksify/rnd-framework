---
id: B25
role: builder
language: sql
tags: [boundaries, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Wrap multi-row invariants in a transaction to guarantee atomicity
specializes: [P-EFFECTS-EDGE-01]
---

### Card B25: Transaction boundaries — specializes the push-effects-to-edges principle for PostgreSQL

**Good:**
```sql
BEGIN;
  UPDATE accounts SET balance = balance - $1 WHERE id = $2;
  UPDATE accounts SET balance = balance + $1 WHERE id = $3;
  INSERT INTO transfers (from_id, to_id, amount) VALUES ($2, $3, $1);
COMMIT;
```

**Worse:**
```python
db.execute("UPDATE accounts SET balance = balance - %s WHERE id = %s", (amount, from_id))
db.execute("UPDATE accounts SET balance = balance + %s WHERE id = %s", (amount, to_id))
db.execute("INSERT INTO transfers VALUES (%s, %s, %s)", (from_id, to_id, amount))
```

**Why good is better:** The worse version is three separate statements. If the process crashes after the first UPDATE, funds are lost from `from_id` but never credited to `to_id`. A `BEGIN`/`COMMIT` block makes all three writes succeed or fail together — no partial state is ever visible to concurrent readers. Use explicit transactions whenever two or more writes must be atomic; auto-commit is the footgun, not the default.
