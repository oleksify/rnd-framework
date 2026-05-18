---
id: JL-V1
role: verifier
language: julia
tags: [critique-evidence, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Write @test abs(x - y) > threshold instead of @test !(x ≈ y atol=…) for "not approximately equal" assertions.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging a test assertion that cannot even parse — if the assertion form is syntactically broken, it silently passes when the macro call is swallowed, meaning no actual check runs.

**Good:**
```julia
@test abs(actual - expected) > 0.001

# positive case — standard form still works fine
@test isapprox(actual, expected; atol=0.001)
```

**Worse:**
```julia
@test !(actual ≈ expected atol=0.001)
```

**Why good is better:** `≈` is a binary operator that accepts `atol` as a keyword argument, but wrapping it in `!()` shifts the AST so Julia's macro expansion fires before the keyword is parsed — the expression `!(x ≈ y atol=0.001)` does not parse and throws a `ParseError` at load time. The explicit `abs(x - y) > threshold` form is always well-formed, makes the tolerance visible, and cannot be silently skipped. When you need the positive case, `isapprox(a, b; atol=…)` with a semicolon is the safe keyword form.
