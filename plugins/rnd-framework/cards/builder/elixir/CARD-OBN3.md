---
id: OBN3
role: builder
language: elixir
tags: [error-handling, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Return the full Oban.Worker return vocabulary — :ok | :discard | {:snooze, sec} | {:error, reason} — never swallow :error.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by ensuring `perform/1` surfaces failures through Oban's return protocol rather than swallowing them inside the worker.

**Good:**
```elixir
@impl Oban.Worker
def perform(%Oban.Job{args: %{"order_id" => id}, attempt: attempt}) do
  case Orders.ship(id) do
    {:ok, _shipment}           -> :ok
    {:error, :not_found}       -> :discard         # gone — no point retrying
    {:error, :warehouse_down}  ->
      {:snooze, 60 * attempt}                      # back off exponentially
    {:error, reason}           -> {:error, reason} # let Oban retry + alert
  end
end
```

**Worse:**
```elixir
@impl Oban.Worker
def perform(%Oban.Job{args: %{"order_id" => id}}) do
  case Orders.ship(id) do
    {:ok, _}       -> :ok
    {:error, _err} -> :ok    # silently suppresses — Oban thinks it succeeded
  end
end
```

**Why good is better:** Returning `:ok` on an error silently marks the job as successful — Oban stops retrying, the failure leaves no trace in the queue, and on-call gets no alert. The full return vocabulary is there for a reason: `:discard` stops retries for permanent failures, `{:snooze, sec}` parks the job for transient backpressure, and `{:error, reason}` retries with backoff and records the failure. Match each failure mode to its correct return. Ref: https://hexdocs.pm/oban/Oban.Worker.html#module-return-values
