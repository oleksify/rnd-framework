---
id: DBG4
role: debugger
language: generic
tags: [debug, observe-only, handoff]
applicable_task_types: [bugfix]
scope: Do not modify project code during diagnosis — read, run, and observe only; hand off to the Builder.
specializes: [P-EFFECTS-EDGE-01]
---

**Good debugger judgment:**
While tracing a data-flow issue, the debugger identifies the fix: a missing condition check in `OrderService.validate`. It documents the exact location, the incorrect behavior, and what the correct behavior should be in the diagnosis report. It does not add the condition check itself. The report section `Recommended Fix` says: "Add guard at `order_service.ex:112` — check `order.status != :cancelled` before calling `apply_discount`."

**Worse debugger judgment:**
The fix is obvious. The debugger edits `order_service.ex` to add the guard, re-runs the tests, confirms they pass, and writes the diagnosis report as if diagnosis was the only work done.

**Why good is better:** The debugger and the Builder have separate roles. The debugger's work product is a diagnosis report with evidence, a located root cause, and a fix recommendation. The Builder's work product is the fix itself, with tests. Combining them skips the Builder's test-first discipline and bypasses the information barrier. A debugger that also fixes the bug is a Builder that skipped the pre-registration — the change lands without a verified test covering the specific root cause.
