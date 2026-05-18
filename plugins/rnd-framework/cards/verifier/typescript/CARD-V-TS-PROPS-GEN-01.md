---
id: V-TS-PROPS-GEN-01
role: verifier
language: typescript
tags: [property, critique-evidence, generators, fast-check]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Distinguish a genuine bug from an over-narrow generator when the fast-check counter-example looks implausible.
specializes: [P-PROPS-02]
---

**Good analysis:**
> `PROPERTY_COUNTER_EXAMPLE` for `parseDate` property. Shrunk counter-example: `{ date: "0000-00-00" }` (seed 2938475). Before marking this a bug, check the generator: `fc.string()` can produce `"0000-00-00"` — a structurally date-like string that is not a real ISO date. `parseDate("0000-00-00")` throwing is correct behavior, not a bug. The generator is over-broad: it should be `fc.date().map(d => d.toISOString().slice(0, 10))` which only produces valid ISO dates. Verdict: the property fails because the generator is wrong, not the implementation. Feedback to Builder: narrow the generator; do not add a guard for `"0000-00-00"`.

**Worse analysis:**
> FAIL. `parseDate` threw an error for input `"0000-00-00"`. The function should handle all string inputs gracefully. Mark as a bug in the implementation.

**Why good is better:** A property failure has two possible root causes: the implementation is wrong, or the generator produced an input outside the function's intended domain. When the counter-example looks implausible — a structurally-valid-but-semantically-invalid value like `"0000-00-00"` — the Verifier must check whether the generator is over-broad before concluding the implementation is buggy. Widening the implementation to accept all generator outputs is often the wrong fix; it adds dead guards for inputs the function will never receive in production. The correct diagnosis distinguishes "generator is wrong" from "implementation is wrong" and tells the Builder which one to change. The worse analysis skips this check and sends the Builder to add guards for impossible inputs.
