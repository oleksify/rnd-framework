---
id: DBG1
role: debugger
language: generic
tags: [debug, root-cause, symptom]
applicable_task_types: [bugfix]
scope: Distinguish the root cause from the symptom before forming a hypothesis about what to fix.
specializes: [P-IMPOSSIBLE-01]
---

**Good debugger judgment:**
A test fails with `NullPointerException` at `UserService:47`. The debugger does not conclude "the bug is at line 47." It traces backward: what value is null, where was it set, and under what condition does it arrive as null? The root cause is a missing guard in the repository layer that allows a deleted user's session to survive. Line 47 is where the null surfaces, not where the bug lives.

**Worse debugger judgment:**
The test failure points at line 47. The debugger adds a null check at line 47 and marks the bug fixed. The next test failure surfaces the same null value at line 83.

**Why good is better:** Fixing the symptom leaves the root cause in place. A null check at the point of failure turns a crash into a silent incorrect state — often worse. The diagnostic question is: what upstream condition caused this value to be wrong? Follow that chain until it terminates in a decision that was made incorrectly, not an effect that was observed incorrectly.
