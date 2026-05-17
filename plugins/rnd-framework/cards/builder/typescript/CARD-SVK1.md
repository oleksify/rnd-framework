---
id: SVK1
role: builder
language: typescript
tags: [boundaries, control-flow, abstraction]
applicable_task_types: [new-feature, bugfix, refactor]
scope: load functions are pure data fetchers; never perform side-effects (writes, logging, redirects via goto) inside them.
specializes: [P-PURE-RENDER-01]
---

**Good:**
```typescript
// +page.server.ts
import type { PageServerLoad } from './$types'

export const load: PageServerLoad = async ({ params, fetch }) => {
  const res = await fetch(`/api/posts/${params.id}`)
  const post = await res.json()
  return { post }
}
```

**Worse:**
```typescript
// +page.server.ts
export const load = async ({ params }) => {
  const post = await db.posts.findOne(params.id)
  await db.analytics.log({ viewed: params.id })  // side-effect in load
  console.log('loaded post', params.id)           // I/O in load
  return { post }
}
```

**Why good is better:** Specializes the pure-render principle for SvelteKit `load` functions. `load` is invoked on the server for SSR, during client navigation, and again on prerender — side-effects that write data or log metrics will run multiple times and in contexts you don't control. Return shaped data; put writes in form actions or API routes where the invocation model is explicit.
