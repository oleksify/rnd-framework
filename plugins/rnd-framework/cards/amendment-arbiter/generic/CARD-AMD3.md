---
id: AMD3
role: amendment-arbiter
language: generic
tags: [amend, rebuild, threshold]
applicable_task_types: [bugfix, infra, new-feature, refactor]
scope: Choose REBUILD over AMEND when the fix requires any behavior change in the implementation.
specializes: [P-IMPOSSIBLE-01]
---

**Good arbiter judgment:**
The pre-registration says "returns HTTP 200 on success." The Verifier flags this as wrong: the operation creates a resource and should return 201. The arbiter checks: does changing 200 → 201 require code changes beyond the status code? If the controller logic, caching behavior, or client contracts depend on 200, this is a behavior shift — route REBUILD. If it is only a constant in an assertion, AMEND is appropriate for the criterion text alone.

**Worse arbiter judgment:**
Any numeric change to a criterion looks narrow, so the arbiter proposes AMEND unconditionally. The Builder gets an amended pre-reg and discovers the response code is wired into three middleware layers.

**Why good is better:** AMEND patches the spec; REBUILD lets the Builder start implementation fresh against corrected criteria. When a criterion change would require the Builder to rethink implementation choices rather than adjust a single value, REBUILD is correct. The test for "mechanical edit" is whether an intelligent reader of the spec change could satisfy the new criterion without revisiting the prior implementation's design decisions.
