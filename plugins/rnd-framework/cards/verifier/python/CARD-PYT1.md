---
id: PYT1
role: verifier
language: python
tags: [critique-evidence, defensive-programming, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Session-scoped fixtures that mutate shared state leak between tests and produce order-dependent failures.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by flagging pytest fixture scope mismatches: a fixture with `scope="session"` that mutates a shared object will bleed state across tests.

**Good review comment:**
> FAIL. The `db_records` fixture at `tests/conftest.py:18` uses `scope="session"` but appends to a list inside the fixture body. Every test that calls it receives the same list object — mutations from one test accumulate and leak into the next. A test that runs first will see zero records; a test that runs third may see two extra. Change to `scope="function"` (the default) so each test gets a fresh list, or make the fixture yield a copy rather than the shared reference.

**Worse review comment:**
> The test setup uses session-scoped fixtures. This should be fine for most use cases, but consider whether state isolation is needed.

**Why good is better:** The good comment names the fixture, its location, the specific mutation, the failure mode (order-dependent results), and two remedies. The worse comment identifies the topic but gives no evidence the mutation is actually happening and provides no actionable next step. Scope mismatch bugs are silent — they produce flaky results rather than immediate errors — so the review comment must name the mechanism, not just flag the pattern.
