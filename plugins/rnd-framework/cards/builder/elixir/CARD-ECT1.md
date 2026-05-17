---
id: ECT1
role: builder
language: elixir
tags: [control-flow, error-handling, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use Ecto.Multi for operations that must succeed or fail together; never issue separate Repo calls and manually roll back on failure.
specializes: [P-EFFECTS-EDGE-01, B7]
---

Specializes the effects-at-the-edge principle and the `with/1` sequencing card by replacing ad-hoc sequential Repo calls with `Ecto.Multi`, which makes the transaction boundary explicit and atomic.

**Good:**
```elixir
def transfer(from_id, to_id, amount) do
  Ecto.Multi.new()
  |> Ecto.Multi.update(:debit,  debit_changeset(from_id, amount))
  |> Ecto.Multi.update(:credit, credit_changeset(to_id, amount))
  |> Repo.transaction()
end

# Caller pattern-matches the named step on failure:
case transfer(from, to, 100) do
  {:ok, _changes}                   -> :ok
  {:error, :debit,  cs, _changes}   -> {:error, :insufficient_funds, cs}
  {:error, :credit, cs, _changes}   -> {:error, :invalid_recipient, cs}
end
```

**Worse:**
```elixir
def transfer(from_id, to_id, amount) do
  with {:ok, _} <- Repo.update(debit_changeset(from_id, amount)),
       {:ok, _} <- Repo.update(credit_changeset(to_id, amount)) do
    :ok
  else
    err ->
      Repo.update(reverse_debit_changeset(from_id, amount))
      err
  end
end
```

**Why good is better:** The worse version issues a compensating write on failure — if that write also fails, the accounts are left in an inconsistent state with no error surfaced. `Ecto.Multi` wraps all steps in a single DB transaction: either all succeed or Postgres rolls back atomically. Named steps also let the caller identify exactly which operation failed without inspecting error shapes.
