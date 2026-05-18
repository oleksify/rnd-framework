---
id: POL4
role: polisher
language: generic
tags: [polish, rollback, discipline]
applicable_task_types: [new-feature, refactor]
scope: Roll back all touched files immediately on any test failure after applying polish mutations.
specializes: [P-EFFECTS-EDGE-01]
---

**Good polisher judgment:**
The polisher applied three mutations — a helper lift and two naming fixes. The test suite reports one failure in an unrelated test file. Rather than investigating whether the failure is a pre-existing flake or caused by the polish, the polisher runs `git restore -- <all touched files>` unconditionally, logs `wave-N: polish: skipped (broke verification)`, and reports which mutations were attempted and which test failed.

**Worse polisher judgment:**
The polisher examines the failing test, concludes it is a flake unrelated to the mutations, and leaves the changes in place. It marks the polish as applied and moves on.

**Why good is better:** The polisher does not have enough context to judge whether a test failure is causal or coincidental. The only safe verdict on a non-PASS test result is rollback. A false negative — leaving breaking changes in place — blocks the next wave and is harder to debug than a conservative rollback. The report records what was attempted, so the orchestrator can decide whether to retry after the flaky test is resolved.
