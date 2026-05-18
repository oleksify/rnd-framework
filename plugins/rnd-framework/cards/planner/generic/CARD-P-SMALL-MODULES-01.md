---
id: P-SMALL-MODULES-01
role: planner
language: generic
tags: [scope, decomposition, boundaries]
applicable_task_types: [new-feature, refactor, infra]
scope: Enforce stable module boundaries by keeping the public API small from the start.
---

**Good module boundary:**
> `users/export.ex` — one function: `export_csv(user_id) :: {:ok, binary} | {:error, atom}`.
> Takes an id, returns bytes or a tagged error. No HTTP, no logging, no config reads.
> Stable API: callers depend on this signature; internals can churn.

**Worse module boundary:**
> `UserManager` — handles registration, auth, export, preferences, and admin flags.
> Callers import `UserManager` for any user-related need. Adding a feature means reading 400 lines to find the right spot.

**Why good is better:** A module with one job and a two-entry public API can be understood in isolation, tested without mocks of unrelated concerns, and changed without surprising callers. A wide module turns every change into an audit: did I break the ten other things that live here? Stable boundaries are not discovered by design — they are enforced by keeping the API small from the start. When a second caller needs something different, that is the right time to split, not day one.
