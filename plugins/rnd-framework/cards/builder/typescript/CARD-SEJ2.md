---
id: SEJ2
role: builder
language: typescript
tags: [boundaries, error-handling, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Sentry.setUser is process-global on Node — set it at the request boundary and clear it in a finally block.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```typescript
// Express middleware
app.use(async (req, res, next) => {
  const user = await resolveUser(req)

  Sentry.setUser({ id: user.id, email: user.email })

  try {
    next()
  } finally {
    Sentry.setUser(null)  // clear before the next request reuses this thread
  }
})
```

**Worse:**
```typescript
const handleRequest = async (req: Request) => {
  const user = await resolveUser(req)
  Sentry.setUser({ id: user.id })
  // no cleanup — next request on this worker inherits the previous user's identity
  return processRequest(req, user)
}
```

**Worse (async leak):**
```typescript
Sentry.setUser({ id: req.user.id })
await longRunningTask()  // another request may interleave here
Sentry.setUser(null)     // too late — interleaved events attributed to wrong user
```

**Why good is better:** Specializes the push-effects-to-the-edge principle for process-global Sentry state. Node.js reuses worker threads across requests; `Sentry.setUser` writes to a global scope store, not a per-request store. Without a `finally` clear, errors from one user get attributed to the identity set by a prior request. Set user context at the request entry point in middleware and clear it unconditionally in `finally`, regardless of success or failure.
