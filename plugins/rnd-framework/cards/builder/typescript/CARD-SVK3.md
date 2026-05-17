---
id: SVK3
role: builder
language: typescript
tags: [boundaries, control-flow, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use redirect() from @sveltejs/kit inside load and actions; goto() in load is silently dropped.
specializes: [P-IMPOSSIBLE-01]
---

**Good:**
```typescript
// +page.server.ts
import { redirect } from '@sveltejs/kit'
import type { PageServerLoad } from './$types'

export const load: PageServerLoad = async ({ locals }) => {
  if (!locals.user) {
    redirect(303, '/login')
  }
  return { user: locals.user }
}
```

**Worse:**
```typescript
import { goto } from '$app/navigation'

export const load = async ({ locals }) => {
  if (!locals.user) {
    goto('/login')  // goto does nothing in a load function; runs client-nav only
  }
  return { user: locals.user }
}
```

**Why good is better:** Specializes the impossible-states principle for SvelteKit navigation. `goto()` is a client-side navigation helper — calling it inside a server `load` function produces no error but also no redirect; the function continues and returns data as if the guard never ran. `redirect()` throws a special `Response` that SvelteKit intercepts on both server and client, making the guard unconditional. Using `goto` in `load` creates a state where unauthenticated users silently receive protected data.
