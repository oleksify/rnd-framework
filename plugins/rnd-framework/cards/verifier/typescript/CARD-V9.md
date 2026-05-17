---
id: V9
role: verifier
language: typescript
tags: [critique-evidence, error-handling, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Promise-rejection tests require expect(...).rejects.toThrow; a try/catch in the test body can silently pass on any throw.
specializes: [P-IMPOSSIBLE-01]
---

**Good review comment:**
> FAIL. The test for rejected `fetchUser('bad-id')` uses a `try/catch` that catches the error and asserts on `error.message`. This pattern passes even if a completely different error is thrown — or if the function throws synchronously rather than rejecting. Replace with `await expect(fetchUser('bad-id')).rejects.toThrow('User not found')` so the assertion is tied to the rejected promise specifically.

**Worse review comment:**
> The test wraps the call in try/catch and checks the error message, which seems reasonable for async error handling.

**Why good is better:** Specializes the impossible-states principle for async test hygiene. A `try/catch` in a test body will catch *any* synchronous throw — a type error, a null dereference, even a typo — and the `catch` block's assertion may then pass on the wrong error. `expect(...).rejects.toThrow` is scoped to the Promise rejection, fails if the promise resolves, and asserts the rejection reason in one step. It closes the gap between "something threw" and "the right thing rejected."
