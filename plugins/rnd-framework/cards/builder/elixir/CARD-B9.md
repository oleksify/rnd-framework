---
id: B9
role: builder
language: elixir
tags: [validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Validate at the Ecto.Changeset boundary; keep business logic clean of raw-input checks.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by ensuring invalid data can never enter the domain: changesets enforce the contract at the boundary so the rest of the codebase handles only validated structs.

**Good:**
```elixir
# Controller — only calls into the domain, no raw-input checks
def create(conn, params) do
  with {:ok, order} <- Orders.create(params), do: json(conn, order)
end

# Domain function — delegates validation to changeset
def create(params) do
  %Order{} |> Order.changeset(params) |> Repo.insert()
end

defmodule Order do
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:user_id, :amount])
    |> validate_required([:user_id, :amount])
    |> validate_number(:amount, greater_than: 0)
  end
end
```

**Worse:**
```elixir
def create(params) do
  if is_nil(params["user_id"]) || params["amount"] <= 0 do
    {:error, :invalid}
  else
    Repo.insert(%Order{user_id: params["user_id"], amount: params["amount"]})
  end
end
```

**Why good is better:** The worse version validates inside business logic — so every new caller must replicate the guard, or skip it. The changeset approach makes the schema the single validation boundary: the domain function trusts its input because invalid data cannot reach it.
