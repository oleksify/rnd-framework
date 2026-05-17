---
id: SUP2
role: builder
language: typescript
tags: [boundaries, validation, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: RLS enforces access at the database — client-side user_id filters are defense-in-depth, not the security boundary.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```typescript
// RLS policy on posts table: auth.uid() = user_id
// Client just queries — the database enforces the boundary
const { data, error } = await supabase
  .from('posts')
  .select('*')

if (error) {
  throw new Error(error.message)
}

return data  // only the authenticated user's rows are returned
```

**Worse:**
```typescript
const userId = supabase.auth.getUser()  // async! returns Promise — this is wrong
// Client-side filter does nothing if RLS is misconfigured or missing
const { data } = await supabase
  .from('posts')
  .select('*')
  .eq('user_id', userId)  // security depends entirely on this line, not the DB

return data
```

**Why good is better:** Specializes the push-effects-to-the-edge principle for database access control. RLS policies run inside PostgreSQL for every query — they cannot be bypassed by a client library bug, network replay, or API key leak. A client `.eq('user_id', ...)` filter is advisory; if it is missing or wrong, all rows are returned. Rely on RLS as the enforcing layer; add client filters only as a performance hint, never as the sole security check.
