---
id: JL1
role: builder
language: julia
tags: [abstraction, control-flow]
applicable_task_types: [new-feature, refactor]
scope: Replace isa-chain conditionals with multiple method definitions to let dispatch do the branching.
specializes: [P-SMALL-MODULES-01]
---

Specializes the small-modules principle by routing type-dependent behaviour through Julia's dispatch mechanism rather than explicit type tests — each method is its own small unit, independently readable and independently extensible.

**Good:**
```julia
process(x::Number)       = "number: $(Float64(x))"
process(x::AbstractString) = "string: $x"
process(x::Vector)       = "vector of $(length(x))"
```

**Worse:**
```julia
function process(x)
    if isa(x, Number)
        return "number: $(Float64(x))"
    elseif isa(x, AbstractString)
        return "string: $x"
    elseif isa(x, Vector)
        return "vector of $(length(x))"
    else
        error("unsupported type: $(typeof(x))")
    end
end
```

**Why good is better:** Adding a new type in the worse version means editing the original function — a violation of open/closed. With dispatch, you add a new method without touching existing ones. The compiler also specialises each method independently, giving better performance. The isa-chain also obscures the contract: the method signatures in the good version make the accepted types machine-checkable and self-documenting.
