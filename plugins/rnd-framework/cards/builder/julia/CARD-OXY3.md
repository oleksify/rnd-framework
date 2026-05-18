---
id: OXY3
role: builder
language: julia
tags: [defensive-programming, error-handling]
applicable_task_types: [new-feature, bugfix]
scope: Guard `staticfiles` with `isdir()` or use `dynamicfiles` to avoid crashes when the directory is absent.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle: `staticfiles` performs an eager directory read at registration time — before any request arrives. If the directory does not exist (e.g., a frontend build has not run yet), Oxygen crashes during startup rather than at request time.

**Good:**
```julia
# Option A: guard with isdir — skip registration if build hasn't run yet
isdir("public") && staticfiles("public", "/static")

# Option B: dynamicfiles — re-reads the directory on every request (better for dev)
dynamicfiles("public", "/static")
```

**Worse:**
```julia
# Crashes at server startup if public/ doesn't exist yet
staticfiles("public", "/static")
```

**Why good is better:** In CI, staging, or a fresh checkout the `public/` directory may not exist until a frontend build step runs. An unguarded `staticfiles` call crashes the Julia process during module initialisation with a confusing `SystemError: opendir`, long before any HTTP request is made. The `isdir` guard makes the absence explicit and non-fatal; `dynamicfiles` avoids the issue entirely by deferring directory access to request time, at the cost of a small per-request stat syscall.
