---
id: JL3
role: builder
language: julia
tags: [error-handling, defensive-programming]
applicable_task_types: [new-feature, bugfix]
scope: Coerce JSON numeric fields through a multi-dispatch helper instead of calling Float64() directly.
specializes: [P-EFFECTS-EDGE-01]
---

External APIs return numeric fields inconsistently — the same field may arrive as a JSON number (`1.23`) or a JSON string (`"1.23"`) depending on the client library version, API version, or edge cases in the data. `Float64(x)` throws when `x` is an `AbstractString`.

**Good:**
```julia
_to_float(x::Number)         = Float64(x)
_to_float(x::AbstractString) = parse(Float64, x)
_to_float(x)                 = throw(ArgumentError("cannot coerce $(typeof(x)) to Float64"))

# Usage
amount = _to_float(response["amount"])
rate   = _to_float(response["exchange_rate"])
```

**Worse:**
```julia
amount = Float64(response["amount"])    # crashes when API returns "1.23" instead of 1.23
rate   = Float64(response["exchange_rate"])
```

**Why good is better:** The worse version crashes at runtime in production with `MethodError: Cannot `convert` an object of type String to an object of type Float64` — a failure that only appears when the API switches representation. The dispatch helper handles both shapes transparently, and the fallback method catches unexpected types with a descriptive error rather than a cryptic stack trace. One definition, used everywhere, ensures consistent coercion across all fields.
