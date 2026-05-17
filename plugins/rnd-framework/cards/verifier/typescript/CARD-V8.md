---
id: V8
role: verifier
language: typescript
tags: [critique-evidence, validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Type-narrowing tests must exercise the actual type guard, not assume the happy-path input.
specializes: [P-IMPOSSIBLE-01]
---

**Good review comment:**
> FAIL. The test for `isAdminUser` passes `{ role: 'admin' }` and asserts the return is `true` — but never tests the narrowing itself. After the guard, does TypeScript know `user` is `AdminUser`? Write a test that tries to access an `AdminUser`-only property inside the `if`-block and confirm the type compiles. Also test the rejection path: `{ role: 'viewer' }` should return `false` and leave `user` typed as the wider union.

**Worse review comment:**
> The test covers the happy path and looks fine. Type guards are tricky so this is probably sufficient.

**Why good is better:** Specializes the impossible-states principle for TypeScript type guard verification. A type guard has two jobs: return the right boolean AND narrow the type in the conditional branch. A test that only checks the return value misses half the contract. The good comment demands evidence that narrowing works and that the rejection path is covered — because a buggy guard that always returns `true` would pass a boolean-only test.
