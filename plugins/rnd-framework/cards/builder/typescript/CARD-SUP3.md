---
id: SUP3
role: builder
language: typescript
tags: [boundaries, error-handling, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: supabase.auth.getUser() is async and must be awaited; on the server, the anon key only sees the JWT claims, not a DB lookup.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```typescript
// Server-side: use service-role key for trusted user lookup
import { createClient } from '@supabase/supabase-js'

const adminClient = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!,
)

const { data: { user }, error } = await adminClient.auth.admin.getUserById(userId)

if (error || !user) {
  throw new Error('User not found')
}
```

**Worse:**
```typescript
// anon key — getUser() here only validates the JWT locally; does NOT
// hit auth.users for fresh data and silently returns stale or revoked info
const { data: { user } } = await supabase.auth.getUser()
```

**Why good is better:** Specializes the push-effects-to-the-edge principle for Supabase auth boundaries. The anon client's `getUser()` re-validates the JWT signature locally — it does not perform a database round-trip, so a revoked or deleted user can still appear valid until the token expires. Server-side trust decisions (role checks, ban enforcement) require the service-role key and `auth.admin.getUserById()`, which hits the database. Use the anon key on the client for UX; use the service-role key on the server for trust.
