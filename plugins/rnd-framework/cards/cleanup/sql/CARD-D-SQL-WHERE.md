---
id: D-SQL-WHERE
role: cleanup
language: sql
tags: [dead-code, commented-out]
applicable_task_types: [refactor]
scope: Remove commented-out WHERE clause predicates rather than preserving them as in-SQL notes.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```sql
SELECT id, user_id, amount, created_at
FROM transactions
WHERE created_at >= NOW() - INTERVAL '30 days'
  -- AND status = 'settled'       -- removed per PM request 2023-08
  -- AND gateway = 'stripe'       -- multi-gateway now, keep all
  AND deleted_at IS NULL;
```

**After:**
```sql
SELECT id, user_id, amount, created_at
FROM transactions
WHERE created_at >= NOW() - INTERVAL '30 days'
  AND deleted_at IS NULL;
```

**Why after is better:** Commented-out SQL predicates are not documentation — they are noise that fragments the readable query logic and implies the predicate might be reinstated. Any reader must evaluate whether `status = 'settled'` is relevant to their current task, find the "removed per PM" note, and conclude it is not. If the predicate's removal was intentional and permanent, delete it; git blame preserves who removed it and why. If the history note is important, it belongs in a migration comment or ADR, not inline SQL.
