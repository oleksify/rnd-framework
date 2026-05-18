---
id: B23
role: builder
language: sql
tags: [validation, boundaries, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Enforce data invariants with database constraints, not application-side checks
specializes: [P-IMPOSSIBLE-01]
---

**Good:**
```sql
CREATE TABLE orders (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id),
  status      text NOT NULL CHECK (status IN ('pending', 'paid', 'cancelled')),
  total_cents integer NOT NULL CHECK (total_cents >= 0),
  UNIQUE (user_id, created_at)
);
```

**Worse:**
```python
def create_order(user_id, status, total_cents):
    if not user_id:
        raise ValueError("user_id required")
    if status not in ('pending', 'paid', 'cancelled'):
        raise ValueError("invalid status")
    if total_cents < 0:
        raise ValueError("total must be non-negative")
    db.execute("INSERT INTO orders VALUES (%s, %s, %s)", ...)
```

**Why good is better:** App-side validation runs only in that one code path — direct DB writes, bulk imports, and concurrent inserts bypass it silently. Postgres constraints fire on every write, unconditionally, atomically. An invalid row is structurally impossible, not just unlikely. Move invariants that belong to the data into the schema; reserve app-side checks for input that is invalid before it reaches the DB.
