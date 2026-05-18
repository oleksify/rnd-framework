---
id: JL-V2
role: verifier
language: julia
tags: [critique-evidence, validation, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Test JSON numeric coercion with both Number and AbstractString inputs so the multi-dispatch helper is fully exercised.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by ensuring each dispatch branch of a type-branching helper has its own test case — a single-input test will pass even when one branch is entirely missing.

**Good:**
```julia
@testset "coercion roundtrip" begin
    @test _to_float(42.0) == 42.0
    @test _to_float("42.0") == 42.0
    @test_throws ArgumentError _to_float(nothing)
end
```

**Worse:**
```julia
@test _to_float(42.0) == 42.0
```

**Why good is better:** External APIs return numeric fields inconsistently — sometimes as JSON numbers (`42.0 :: Float64`), sometimes as JSON strings (`"42.0" :: String`). The multi-dispatch helper `_to_float` defines separate methods for `Number` and `AbstractString`. A test that only calls `_to_float(42.0)` never exercises the `AbstractString` method and will pass even if that method is absent or wrong. The good form covers both dispatch paths and adds a boundary check for an unsupported input type, giving confidence that the converter is complete.
