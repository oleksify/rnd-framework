---
id: JL4
role: builder
language: julia
tags: [control-flow, abstraction]
applicable_task_types: [new-feature, refactor, bugfix]
scope: Give every branch of a function the same concrete return type to keep it type-stable.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-state principle: a function that returns `Union{T, Nothing}` forces every caller to handle `nothing` as a legitimate value — making the "not found" path indistinguishable from a valid result at the type level. Push the error to the function boundary instead.

**Good:**
```julia
struct NotFoundError <: Exception
  id::Int
end

function lookup(db, id::Int)::User
  user = get(db, id, nothing)
  isnothing(user) && throw(NotFoundError(id))
  user                      # always a User — return type is concrete
end

# Caller never needs to check for nothing
user = lookup(db, 42)
println(user.name)
```

**Worse:**
```julia
function lookup(db, id::Int)::Union{User, Nothing}
  get(db, id, nothing)
end

# Every caller must handle both branches
user = lookup(db, 42)
if isnothing(user)
  error("not found")
end
println(user.name)
```

**Why good is better:** `Union{T, Nothing}` infects callers: every call site must add a `nothing` guard, and forgetting one causes a runtime `MethodError` or `UndefVarError` rather than a type error. The compiler cannot specialise generated code for a union return type as efficiently as for a concrete type. Throwing at the boundary keeps the happy path type-stable and delegates error handling to wherever it can be most usefully addressed.
