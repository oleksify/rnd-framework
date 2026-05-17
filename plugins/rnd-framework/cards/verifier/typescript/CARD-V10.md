---
id: V10
role: verifier
language: typescript
tags: [critique-evidence, validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use objectContaining for partial-match assertions; exact object equality fails on incidental fields.
specializes: [P-IMPOSSIBLE-01]
---

**Good review comment:**
> NEEDS ITERATION. The test asserts `expect(spy).toHaveBeenCalledWith({ userId: '42' })` — but the actual call passes `{ userId: '42', timestamp: expect.any(Number) }`. The exact-match assertion will fail in any environment that populates `timestamp`. Replace with `expect(spy).toHaveBeenCalledWith(expect.objectContaining({ userId: '42' }))` to assert only the fields under test.

**Worse review comment:**
> The spy assertion checks the argument shape. Looks correct from the test description.

**Why good is better:** Specializes the impossible-states principle for spy/mock argument verification. Exact object equality in `toHaveBeenCalledWith` creates a brittle test that breaks whenever an incidental field is added (timestamp, request ID, trace context). `expect.objectContaining` asserts the contract — the fields that matter — while tolerating fields the caller legitimately adds. Use exact equality only when the full argument shape is itself part of the contract being verified.
