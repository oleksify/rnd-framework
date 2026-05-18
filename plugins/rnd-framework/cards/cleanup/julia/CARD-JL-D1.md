---
id: JL-D1
role: cleanup
language: julia
tags: [dead-code, defensive-programming]
applicable_task_types: [refactor]
scope: Remove Revise from [deps] in projects built with PackageCompiler; load it as a dev-only global-env dependency instead.
specializes: [P-IMPOSSIBLE-01]
---

**Before:**
```toml
# Project.toml
[deps]
HTTP = "..."
JSON3 = "..."
Revise = "1bc81286-8c58-5bd4-..."
Oxygen = "..."
```

**After:**
```toml
# Project.toml — Revise entry removed
[deps]
HTTP = "..."
JSON3 = "..."
Oxygen = "..."
```

```julia
# dev/startup.jl — loaded via ~/.julia/config/startup.jl in interactive sessions only
push!(LOAD_PATH, "@v#.#")
try
    using Revise
catch
end
```

**Why after is better:** PackageCompiler precompiles every package listed under `[deps]` into the sysimage. Revise hooks into the Julia loader to enable live code reloading — those hooks assume an interactive REPL and fail to initialize inside a compiled sysimage, causing the build to error. Keeping Revise as a project dependency is dead weight in production: it will never be used at runtime, yet its presence breaks the release build. Moving it to a dev-only global-environment load (guarded by a `try/catch`) preserves the interactive workflow for development without touching the compiled artifact.
