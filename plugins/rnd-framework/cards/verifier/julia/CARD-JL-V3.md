---
id: JL-V3
role: verifier
language: julia
tags: [validation, abstraction]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Group @testset blocks by behavior, not by source location, so the failure ribbon is self-documenting.
specializes: [P-SMALL-MODULES-01]
---

Specializes the small-modules principle at the test level: a testset whose label names a source line range collapses multiple behaviors into one opaque block, forcing the reader to open the source to understand the failure.

**Good:**
```julia
@testset "Account.deposit" begin
    @testset "rejects negative amount" begin
        @test_throws DomainError deposit(account, -10.0)
    end

    @testset "increments balance on success" begin
        deposit(account, 50.0)
        @test account.balance == 150.0
    end
end
```

**Worse:**
```julia
@testset "lines 30-60 of accounts.jl" begin
    @test_throws DomainError deposit(account, -10.0)
    account2 = Account(100.0)
    deposit(account2, 50.0)
    @test account2.balance == 150.0
end
```

**Why good is better:** Test.jl prints the full `@testset` label hierarchy on failure: `Account.deposit › rejects negative amount FAILED`. That label IS the documentation — it tells the reader what invariant broke without opening any file. A label like `"lines 30-60 of accounts.jl"` provides no behavioral information and rots the moment the file changes. Group by the behavior you are asserting; keep each inner testset to one observable outcome.
