---
id: D-SQL-VIEWS
role: cleanup
language: sql
tags: [dead-code, dead-views]
applicable_task_types: [refactor]
scope: Drop views and table columns that no application query or report selects from.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```sql
-- Created for the Q2 export pipeline, which was replaced by a direct table query
CREATE VIEW v_order_export AS
SELECT o.id, o.created_at, o.total, u.email
FROM orders o
JOIN users u ON u.id = o.user_id;

-- Column added for a feature flag that was removed
ALTER TABLE products ADD COLUMN legacy_sku VARCHAR(64);
```

**After:**
```sql
DROP VIEW IF EXISTS v_order_export;

-- Migration to remove orphan column:
ALTER TABLE products DROP COLUMN legacy_sku;
```

**Why after is better:** Dead views waste the query planner's time during dependency resolution and mislead developers browsing the schema. Orphan columns consume storage, appear in `SELECT *` results, and cause confusion about whether they carry meaningful data. Before dropping, confirm no consumer by searching application code (`grep -r "v_order_export\|legacy_sku" app/`) and checking any reporting tools or ETL jobs. Drop in a migration so the change is version-controlled and reversible.
