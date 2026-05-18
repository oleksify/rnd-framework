---
id: D-SQL-ENUM
role: cleanup
language: sql
tags: [dead-code, enum-values]
applicable_task_types: [refactor]
scope: Remove unused enum values only after confirming no row stores them and no application code produces them.
specializes: [P-IMPOSSIBLE-01]
---

**Before:**
```sql
CREATE TYPE order_status AS ENUM (
  'pending',
  'processing',
  'shipped',
  'delivered',
  'cancelled',
  'refunded',
  'on_hold'    -- introduced for a feature that was never shipped
);
```

**After:**
```sql
-- Remove 'on_hold' after verifying:
--   SELECT COUNT(*) FROM orders WHERE status = 'on_hold';  → 0
--   grep -r "on_hold" app/ → no application producer

ALTER TYPE order_status RENAME TO order_status_old;
CREATE TYPE order_status AS ENUM ('pending', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded');
ALTER TABLE orders ALTER COLUMN status TYPE order_status USING status::text::order_status;
DROP TYPE order_status_old;
```

**Why after is better:** Unused enum values widen the set of values application code must handle defensively, mislead readers about what states actually occur, and complicate exhaustive `CASE` expressions. PostgreSQL does not allow `ALTER TYPE ... DROP VALUE` directly — recreation is required. Before proceeding, run the row-count query and the application grep to prove zero usage; an enum value that appears in a configuration file or seed script counts as "in use".
