---
id: ECT4
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Repo.insert/1 returns {:ok, struct} or {:error, changeset} — code that ignores the error tuple or matches with an unguarded := is wrong.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging the assumption that a Repo operation always succeeds — an assumption that silently discards changeset errors or crashes on constraint violations.

**Good audit output:**
> `Orders.place/1` at `lib/my_app/orders.ex:31` calls `{:ok, order} = Repo.insert(changeset)`. This is a match-or-crash: if the changeset is invalid (e.g., a unique constraint violation on `order_number`), the process crashes with a `MatchError` and the caller receives a 500. The function signature returns `{:ok, order} | {:error, changeset}` — but the crash path is unreachable by the caller. Flag: replace with a `case` or `with` that surfaces `{:error, cs}` to the caller instead of crashing.

**Worse audit output:**
> The code uses `{:ok, order} = Repo.insert(changeset)`. This is a common Elixir pattern for asserting success.

**Why good is better:** `= Repo.insert(...)` is an assertion, not error handling — it crashes the process on any failure. In a Phoenix request, that means a 500 response and no feedback to the caller about what was invalid. The good output distinguishes "asserting success" (appropriate in tests or seeds) from "handling user input" (requires pattern matching on both arms). The worse output calls it "common" without checking whether the failure path is reachable from user-controlled input.
