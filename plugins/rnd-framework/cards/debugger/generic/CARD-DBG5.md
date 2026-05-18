---
id: DBG5
role: debugger
language: generic
tags: [debug, failing-test, prove-the-bug]
applicable_task_types: [bugfix]
scope: Write a failing test that reproduces the bug before concluding what the root cause is.
specializes: [P-MEASURE-01]
---

**Good debugger judgment:**
The debugger has a hypothesis: `Cart.total` returns the wrong value when a discount is applied to a zero-quantity item. Before finalizing the diagnosis, it writes a minimal test: `assert Cart.total(%{items: [%{qty: 0, price: 10, discount: 0.5}]}) == 0`. The test fails with the current code and the actual value shows what the function returns instead. This confirms the hypothesis and produces the regression test the Builder will need.

**Worse debugger judgment:**
The debugger reads the function, concludes "the discount is applied before the zero-quantity check," writes a diagnosis report describing the issue, and considers the investigation complete. The Builder implements a fix but has no failing test to drive the correct behavior.

**Why good is better:** A hypothesis without a failing test is a claim without evidence. Writing the test serves two purposes: it validates the hypothesis (if the test does not fail, the hypothesis is wrong) and it hands the Builder a concrete, executable specification of the bug. A diagnosis report that includes a failing test is an unambiguous contract for the fix; a narrative description invites interpretation errors.
