---
id: P1
role: planner
language: generic
tags: [spec-shape, scope, decomposition]
applicable_task_types: [new-feature, infra]
scope: medium
specializes: [P-SMALL-MODULES-01]
---

### Card P1: Spec that constrains size and shape

**Good spec:**
> Add JSON export for user preferences.
>
> Constraints:
> - Single function in `users/export.py`, no new classes
> - Output: stdout, valid JSON, one user per call
> - Input: user_id (int), no other parameters
> - Out of scope: bulk export, alternate formats, encryption, async
> - Hard cap: 40 lines including imports

**Worse spec:**
> Implement a flexible, extensible user data export system supporting JSON output. Design for future formats and bulk export capability. Follow best practices for separation of concerns.

**Why good is better:** The good spec constrains the size, the shape, and the scope. It tells the builder what *not* to build. The worse spec invites the enterprise sludge failure mode — flexibility for needs we don't have, extensibility for futures we haven't validated, "best practices" interpreted as "more layers."
