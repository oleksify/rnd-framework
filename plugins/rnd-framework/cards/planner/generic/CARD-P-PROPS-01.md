---
id: P-PROPS-01
role: planner
language: generic
tags: [property, validation, scope]
applicable_task_types: [docs, config, bugfix]
scope: Write markdown-bullet property claims for invariants that do not need a runner.
specializes: [P-SMALL-MODULES-01]
---

**Good property claim:**
> ```
> Properties:
>   - encode_decode_roundtrip: forall input matching valid_utf8, decode(encode(input)) == input
>   - empty_input_returns_empty: forall input matching empty_string, encode(input) == ""
> ```
> Each bullet names one invariant and states the quantifier, the constraint, and the expected outcome. No runner is needed — the Verifier reads these as prose claims and checks them by reasoning or light scripting.

**Worse property claim:**
> ```
> Properties:
>   - works correctly for all inputs
>   - edge cases are handled
> ```
> Vague claims that cannot be falsified. The Verifier cannot construct a counter-example or confirm coverage. "Works correctly" is not a checkable property.

**Why good is better:** A markdown-bullet property claim is the lightest shape — no runner invocation, no sibling file. But "light" only earns its place when the invariant is concrete: a quantifier (`forall`), a generator constraint, and an expected outcome. Vague claims give the Verifier nothing to verify against and silently become approvals of untested behavior. Use this shape for `docs` and `config` tasks where the invariant is simple enough to express in one line and doesn't need StreamData or fast-check to explore the input space.
