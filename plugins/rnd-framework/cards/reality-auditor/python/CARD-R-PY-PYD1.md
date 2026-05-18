---
id: R-PY-PYD1
role: reality-auditor
language: python
tags: [anomaly, cross-check, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Pydantic model examples in docstrings or README must be verified against model_validate at runtime, not read and accepted.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by requiring that Pydantic schema documentation be executed rather than read: a schema example that passes visually may fail validation due to coercion rules, validator side effects, or version differences between Pydantic v1 and v2.

**Good audit observation:**
> `PaymentRequest` at `schemas/payment.py` has a docstring example: `PaymentRequest(amount=100, currency="USD", idempotency_key="abc")`. Running `from schemas.payment import PaymentRequest; PaymentRequest.model_validate({"amount": 100, "currency": "USD", "idempotency_key": "abc"})` raises `ValidationError: idempotency_key must be a UUID`. The docstring example uses a bare string, but the field is typed `UUID` — Pydantic v2 does not coerce plain strings to UUID by default without `model_config = ConfigDict(arbitrary_types_allowed=True)`. The documented example is wrong and will mislead any caller who copies it. Either fix the example to use a valid UUID string, or add a `BeforeValidator` that coerces strings to UUID.

**Worse audit observation:**
> The Pydantic model has docstring examples showing how to construct a `PaymentRequest`. The field types look appropriate for the use case.

**Why good is better:** The good observation executes `model_validate` against the documented example and finds a validation error the docstring hides. The worse observation reads the example and the type annotations and decides they look compatible — without running them. Pydantic validation behavior depends on coercion mode, validators, and library version; visual inspection of a schema example is not a substitute for execution.
