---
id: D-SQL-INDEX
role: cleanup
language: sql
tags: [dead-code, duplicate-indexes]
applicable_task_types: [refactor]
scope: Drop indexes whose column prefix is already fully covered by an existing wider composite index.
specializes: [P-IMPOSSIBLE-01]
---

**Before:**
```sql
-- Added when user_id queries were the only access pattern
CREATE INDEX idx_orders_user_id ON orders (user_id);

-- Added later for user+status queries — covers user_id as a leading prefix
CREATE INDEX idx_orders_user_status ON orders (user_id, status);
```

**After:**
```sql
-- idx_orders_user_id is redundant: any query using user_id alone can use the
-- composite index with the same efficiency via its leading-column prefix.
DROP INDEX idx_orders_user_id;

CREATE INDEX idx_orders_user_status ON orders (user_id, status);
```

**Why after is better:** A composite index `(user_id, status)` satisfies any query that filters on `user_id` alone because the index is sorted by `user_id` first. Keeping `idx_orders_user_id` alongside it means every INSERT/UPDATE/DELETE on `orders` pays the write cost of maintaining both indexes with no read benefit. Confirm the redundancy with `EXPLAIN` on representative queries; drop the narrower index if the planner already chose the composite one.
