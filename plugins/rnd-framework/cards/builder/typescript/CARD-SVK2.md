---
id: SVK2
role: builder
language: typescript
tags: [boundaries, validation, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Server-only secrets belong in +page.server.ts; +page.ts load functions run on both client and server.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```typescript
// +page.server.ts — runs server-side only
import { STRIPE_SECRET_KEY } from '$env/static/private'
import type { PageServerLoad } from './$types'

export const load: PageServerLoad = async () => {
  const charges = await fetchCharges(STRIPE_SECRET_KEY)
  return { charges }
}
```

**Worse:**
```typescript
// +page.ts — runs on client AND server; secret will be bundled to the browser
import { STRIPE_SECRET_KEY } from '$env/static/private'  // build error or leak

export const load = async () => {
  const charges = await fetchCharges(STRIPE_SECRET_KEY)
  return { charges }
}
```

**Why good is better:** Specializes the push-effects-to-the-edge principle for SvelteKit's server boundary. `+page.ts` is a universal load function — Vite bundles it for the browser, so any import of `$env/static/private` in a `+page.ts` is either a build error or a secret bundled into the client. `+page.server.ts` never reaches the client bundle; it is the correct location for credentials, DB connections, and private API calls.
