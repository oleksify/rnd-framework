---
id: OBN-RA3
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Audit calls to Oban.insert!/2 — it raises on changeset error; production callers should use Oban.insert/2 and handle {:error, changeset}.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging that `insert!` makes an invalid-job error unrepresentable as a handled return value — it becomes an unhandled exception instead.

**Good audit output:**
> `lib/my_app/orders.ex:47` calls `Oban.insert!(SendConfirmationWorker.new(args))`. `Oban.insert!/2` raises `Ecto.InvalidChangesetError` if the job changeset is invalid (e.g., a nil `:args` field, a negative `:max_attempts`, or a constraint violation). This call is inside `Orders.complete/1` which is invoked from the HTTP controller with no rescue block. A bad `args` value will return a 500 to the client and log an unhandled exception instead of a structured error. Flag: replace with `Oban.insert/2` and match on `{:ok, _job} | {:error, changeset}`. Ref: https://hexdocs.pm/oban/Oban.html#insert!/2

**Worse audit output:**
> The code uses `Oban.insert!` to enqueue jobs. This is a standard Oban API call.

**Why good is better:** The worse output confirms the API exists without checking the failure mode. `Oban.insert!` is appropriate when the caller treats a bad changeset as a programming error (e.g., in tests or seeding scripts) — not in production request handlers where the job schema depends on runtime input. The good output names the call site, the exception type, the propagation path, and the fix.
