---
id: JL-RA3
role: reality-auditor
language: julia
tags: [anomaly, skepticism, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Fully-qualified parent-module references inside submodules assume the parent is fully loaded when the submodule evaluates — an assumption that is false during include-order initialization.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the side-effect edge-case principle by flagging the assumption that `ParentModule.Sibling` is resolvable at `include()` time — in a multi-file Julia package the submodule is evaluated before the parent finishes loading, so the fully-qualified path resolves to `UndefVarError` or a stale partial binding.

**Good audit output:**
> `MyApp.Services.Sync` at `lib/myapp/services/sync.jl:8` calls `MyApp.Schemas.Event(...)` directly. `sync.jl` is `include()`-d inside `MyApp.Services`, which is itself included from `MyApp` before `MyApp.Schemas` is included at line 14 of `MyApp.jl`. At the time `sync.jl` evaluates, `MyApp.Schemas` does not yet exist in the module graph — the reference will resolve at first call rather than load time, but any method redefinition or precompilation cycle can make this order-dependent and produce an `UndefVarError`. Flag: replace `MyApp.Schemas.Event(...)` with `using ..Schemas; Schemas.Event(...)` — the relative `..` import is resolved lazily through the already-established parent scope and is not order-sensitive.

**Worse audit output:**
> The code references `MyApp.Schemas.Event`. This is a valid fully-qualified name.

**Why good is better:** A fully-qualified name is syntactically valid but semantically fragile when used inside a submodule evaluated during `include()`. The good output traces the specific `include()` ordering, identifies the exact file and line, and names the fix. The worse output confirms legality without checking whether the referenced module exists at the time the submodule is first evaluated.
