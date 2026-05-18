---
id: DBG2
role: debugger
language: generic
tags: [debug, minimal-repro, isolation]
applicable_task_types: [bugfix]
scope: Strip the reproduction case to its minimum before concluding anything about the root cause.
specializes: [P-SMALL-MODULES-01]
---

**Good debugger judgment:**
A full test suite run fails on test 47 of 200. The debugger first confirms the failure is reproducible in isolation: run test 47 alone. Then strips inputs: does the failure require a full database state, or just one record with a specific field? It removes each input element until removing one more makes the failure disappear — that element is load-bearing. The minimal repro is one record with `status: "deleted"` — everything else was noise.

**Worse debugger judgment:**
The debugger works with the full test suite as-is, reasoning about 200 tests and a full database fixture. Hypotheses about the root cause must account for everything the test touches, making diagnosis slow and uncertain.

**Why good is better:** A minimal repro has two concrete benefits. First, it proves which inputs are necessary — anything that can be removed without changing the failure is unrelated to the bug. Second, it produces a standalone failing case that the Builder can use as a regression test. A repro that requires a full system is not portable; a repro that requires one specific record is.
