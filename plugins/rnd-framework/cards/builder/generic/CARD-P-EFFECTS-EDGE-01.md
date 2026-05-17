---
id: P-EFFECTS-EDGE-01
role: builder
language: generic
tags: [abstraction, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: medium
---

### Card P-EFFECTS-EDGE-01: Push effects to the edges; keep the core pure

**Good:**
```elixir
# Pure core — no I/O, no side effects
defmodule Invoice do
  def calculate(line_items, tax_rate) do
    subtotal = line_items |> Enum.map(& &1.amount) |> Enum.sum()
    %{subtotal: subtotal, tax: subtotal * tax_rate, total: subtotal * (1 + tax_rate)}
  end
end

# Effectful edge — I/O happens here only
def handle(%{"items" => items, "tax_rate" => rate}, _conn) do
  totals = Invoice.calculate(items, rate)
  Repo.insert!(%Order{totals: totals})
  json(conn, totals)
end
```

**Worse:**
```elixir
def handle(%{"items" => items, "tax_rate" => rate}, _conn) do
  subtotal = Enum.sum(Enum.map(items, & &1["amount"]))
  Repo.insert!(%Order{subtotal: subtotal, tax: subtotal * rate})
  json(conn, %{subtotal: subtotal, total: subtotal * (1 + rate)})
end
```

**Why good is better:** The worse version tangles business logic with DB writes and HTTP rendering — the calculation is untestable without a database and a conn struct. The good version separates computation from I/O: `Invoice.calculate/2` is a pure function testable with a single call, and the edge function is thin enough to read at a glance. Push I/O to the boundary; keep every decision point in testable, side-effect-free code.
