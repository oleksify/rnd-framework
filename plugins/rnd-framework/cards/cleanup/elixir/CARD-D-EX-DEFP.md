---
id: D-EX-DEFP
role: cleanup
language: elixir
tags: [dead-code, orphan-helpers]
applicable_task_types: [refactor]
scope: Delete private defp helpers that are no longer called from any clause within the same module.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```elixir
defmodule Billing.Invoice do
  def generate(order), do: build_line_items(order)

  defp build_line_items(order) do
    Enum.map(order.items, &format_line_item/1)
  end

  defp format_line_item(item) do
    %{sku: item.sku, qty: item.quantity, price: item.price}
  end

  defp apply_discount(total, code) do   # called by old generate/2 overload, now removed
    Discounts.apply(total, code)
  end
end
```

**After:**
```elixir
defmodule Billing.Invoice do
  def generate(order), do: build_line_items(order)

  defp build_line_items(order) do
    Enum.map(order.items, &format_line_item/1)
  end

  defp format_line_item(item) do
    %{sku: item.sku, qty: item.quantity, price: item.price}
  end
end
```

**Why after is better:** `defp` is module-private: no outside caller can reach it, so if no clause within the module references it, it is guaranteed dead. The Elixir compiler emits an "unused function" warning for exactly this pattern — treat that warning as a required deletion, not an advisory. Confirm with `grep -n "apply_discount" lib/billing/invoice.ex` before removing, because pattern-matched multi-clause defp can appear at multiple sites.
