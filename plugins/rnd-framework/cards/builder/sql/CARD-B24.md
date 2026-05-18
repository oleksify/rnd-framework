---
id: B24
role: builder
language: sql
tags: [boundaries, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use INSERT ... ON CONFLICT for atomic, race-free upserts
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```sql
INSERT INTO user_settings (user_id, key, value)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, key)
DO UPDATE SET value = EXCLUDED.value, updated_at = now();
```

**Worse:**
```python
row = db.fetchone(
    "SELECT id FROM user_settings WHERE user_id = %s AND key = %s",
    (user_id, key)
)
if row:
    db.execute("UPDATE user_settings SET value = %s WHERE id = %s", (value, row.id))
else:
    db.execute("INSERT INTO user_settings (user_id, key, value) VALUES (%s, %s, %s)",
               (user_id, key, value))
```

**Why good is better:** The SELECT-then-INSERT/UPDATE pattern has a race: two concurrent requests both see no row, both INSERT, one fails with a unique-violation error. The `ON CONFLICT DO UPDATE` form is a single atomic statement — Postgres handles the conflict internally with no race window. The write is also idempotent: replaying it yields the same result, which simplifies retry logic and event-driven consumers.
