---
id: EX-PROPS-GEN-MUTUAL
role: builder
language: elixir
tags: [property, generators, constraints, StreamData]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use StreamData.bind/2 to generate values with mutual constraints instead of post-hoc filter/discard.
specializes: [P-PROPS-01]
---

**Good:**
```elixir
# Order generator: positive total AND at least one item — enforced at generation time.
order_gen =
  StreamData.bind(
    StreamData.list_of(StreamData.positive_integer(), min_length: 1),
    fn items ->
      total = Enum.sum(items)
      StreamData.constant(%{items: items, total: total})
    end
  )

property "order total equals sum of items" do
  check all order <- order_gen do
    assert Order.verify_total(order) == :ok
  end
end
```
`total` is always consistent with `items` by construction; shrinking preserves the constraint.

**Worse:**
```elixir
# Generates items and total independently, then filters — most values are discarded.
bad_gen =
  StreamData.filter(
    StreamData.tuple({
      StreamData.list_of(StreamData.positive_integer(), min_length: 1),
      StreamData.positive_integer()
    }),
    fn {items, total} -> Enum.sum(items) == total end
  )
```
The filter ratio is astronomically low — nearly every generated pair is discarded. StreamData emits a "too many discards" error, and shrinking breaks the constraint, producing invalid inputs.

**Why good is better:** `StreamData.bind/2` threads a generated value into a dependent generator, so the constraint holds at construction time. Shrinking a `bind`-composed generator respects the dependency — StreamData shrinks the items list first, then recomputes the dependent total. A post-hoc `filter` discards most of the generation budget and breaks shrinking because the shrunken values no longer satisfy the predicate. Reach for `bind` whenever two fields in your domain are mathematically or semantically related: totals, checksums, balanced trees, correlated date ranges.
