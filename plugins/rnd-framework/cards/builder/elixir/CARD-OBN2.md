---
id: OBN2
role: builder
language: elixir
tags: [validation, boundaries, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use Oban unique constraints to deduplicate job insertion — not a SELECT-then-insert guard in application code.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by making duplicate job scheduling unrepresentable at the queue level, so concurrent callers cannot race past an application-code guard.

**Good:**
```elixir
defmodule MyApp.Workers.ProcessInvoice do
  use Oban.Worker,
    queue: :billing,
    unique: [period: 300, fields: [:worker, :args]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"invoice_id" => id}}) do
    id |> Invoices.get!() |> Invoices.process()
  end
end

# Caller — just insert; uniqueness is Oban's problem
Oban.insert(MyApp.Workers.ProcessInvoice.new(%{invoice_id: inv.id}))
```

**Worse:**
```elixir
# Caller — races under concurrent load
existing = Repo.one(from j in Oban.Job,
  where: j.worker == "MyApp.Workers.ProcessInvoice"
    and fragment("args->>'invoice_id' = ?", ^to_string(inv.id)))

unless existing, do: Oban.insert(MyApp.Workers.ProcessInvoice.new(%{invoice_id: inv.id}))
```

**Why good is better:** The SELECT-then-insert pattern has a classic TOCTOU race: two concurrent callers both see no existing job and both enqueue one. Oban's `unique` option enforces deduplication with a database-level constraint within the `period` window — no race is possible. Push the invariant into the queue contract; keep callers oblivious to dedup logic. Ref: https://hexdocs.pm/oban/Oban.Job.html#module-unique-jobs
