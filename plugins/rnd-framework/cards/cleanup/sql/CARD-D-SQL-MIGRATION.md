---
id: D-SQL-MIGRATION
role: cleanup
language: sql
tags: [dead-code, stale-migrations]
applicable_task_types: [refactor]
scope: Identify migration steps whose schema changes were superseded by a later migration and flag them for documentation.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```sql
-- 20230401_add_status_column.sql
ALTER TABLE orders ADD COLUMN status VARCHAR(32) DEFAULT 'pending';

-- 20230415_change_status_to_enum.sql
ALTER TABLE orders DROP COLUMN status;
ALTER TABLE orders ADD COLUMN status order_status NOT NULL DEFAULT 'pending';

-- 20231102_add_status_index.sql  (references the varchar column shape)
CREATE INDEX idx_orders_status ON orders (status);  -- already exists from 20230415
```

**After:**
```sql
-- 20230401 and 20230415 are historical — do not delete them (migration runners
-- track applied files by filename). Document the supersession in 20230415:
-- "This migration supersedes 20230401: status column converted to enum type."

-- 20231102: remove the duplicate; index already created in 20230415
-- Either: delete 20231102 before it is applied, or add an existence guard:
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
```

**Why after is better:** Migration files that are already applied cannot be deleted — the migration runner records their checksums and will error if they go missing. Instead, annotate superseded migrations with a comment pointing to the later file. For unapplied migrations that duplicate work, remove them before they run. For applied duplicates that would error on re-run, add `IF NOT EXISTS` guards or `DO $$ BEGIN ... EXCEPTION WHEN ... END $$` blocks to make them idempotent.
