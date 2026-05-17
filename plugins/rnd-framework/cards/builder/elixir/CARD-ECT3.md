---
id: ECT3
role: builder
language: elixir
tags: [validation, boundaries, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Route both insert and update through a changeset; never bypass with Repo.insert!/1 of a bare struct.
specializes: [P-IMPOSSIBLE-01, B9]
---

Specializes the impossible-states principle and the Ecto changeset boundary card by enforcing that every write — insert or update — passes through changeset validation so invalid data cannot reach the database.

**Good:**
```elixir
defmodule MyApp.Products.Product do
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :price, :sku])
    |> validate_required([:name, :price, :sku])
    |> validate_number(:price, greater_than: 0)
    |> unique_constraint(:sku)
  end
end

# Insert and update share the same validation path:
def create(attrs), do: %Product{} |> Product.changeset(attrs) |> Repo.insert()
def update(product, attrs), do: product |> Product.changeset(attrs) |> Repo.update()
```

**Worse:**
```elixir
# Bypasses validation on insert; also loses unique_constraint check
def create(attrs) do
  Repo.insert!(%Product{
    name:  attrs["name"],
    price: attrs["price"],
    sku:   attrs["sku"]
  })
end
```

**Why good is better:** `Repo.insert!/1` of a bare struct skips all changeset validations and constraint checks — a zero-price product, a duplicate SKU, or a missing name silently enters the database. The changeset is the single validation boundary: both create and update paths share it, so adding a new validation rule applies everywhere automatically. The bang variant also raises rather than returning `{:error, changeset}`, eliminating the ability to return structured feedback to callers.
