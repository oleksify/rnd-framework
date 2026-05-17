---
id: B7
role: builder
language: elixir
tags: [control-flow, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use with/1 to sequence fallible steps; keep effects at the edge, not inside the chain.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by confining I/O to the `with` match clauses and keeping the success body free of further fallible calls.

**Good:**
```elixir
def process_order(params) do
  with {:ok, user}   <- Repo.fetch(User, params["user_id"]),
       {:ok, item}   <- Repo.fetch(Item, params["item_id"]),
       {:ok, charge} <- Billing.charge(user, item.price) do
    {:ok, build_receipt(user, item, charge)}
  end
end
```

**Worse:**
```elixir
def process_order(params) do
  case Repo.fetch(User, params["user_id"]) do
    {:ok, user} ->
      case Repo.fetch(Item, params["item_id"]) do
        {:ok, item} ->
          case Billing.charge(user, item.price) do
            {:ok, charge} -> {:ok, build_receipt(user, item, charge)}
            err -> err
          end
        err -> err
      end
    err -> err
  end
end
```

**Why good is better:** The nested `case` version grows one indent per step, making the error path repetitive and the happy path hard to follow. `with/1` flattens the sequence: each line names a step and its expected shape; the `do` block only runs on full success. Effects still live at the clause level — pure assembly (`build_receipt`) is pushed into the success body, matching the effects-at-edge principle.
