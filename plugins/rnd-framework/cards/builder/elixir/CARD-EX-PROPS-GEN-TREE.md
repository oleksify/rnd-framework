---
id: EX-PROPS-GEN-TREE
role: builder
language: elixir
tags: [property, generators, recursion, StreamData]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use StreamData.tree/2 to generate arbitrarily-deep recursive structures instead of fixed-depth lists.
specializes: [P-PROPS-01]
---

**Good:**
```elixir
# Binary-tree generator: leaf or {left, right} node up to arbitrary depth.
leaf = StreamData.integer()

tree =
  StreamData.tree(leaf, fn subtree ->
    StreamData.tuple({subtree, subtree})
  end)

property "sum is non-negative for trees of non-negative integers" do
  check all t <- tree do
    assert Tree.sum(t) >= 0
  end
end
```
StreamData controls depth automatically; shrinking reduces to the minimal failing subtree.

**Worse:**
```elixir
# Fixed-depth nesting: misses depth-dependent bugs entirely.
nested =
  StreamData.list_of(
    StreamData.list_of(
      StreamData.list_of(StreamData.integer(), max_length: 3),
      max_length: 3
    ),
    max_length: 3
  )
```
Three-level nesting is hard-coded; the generator never produces a four-level tree that might expose a stack overflow or base-case bug.

**Why good is better:** `StreamData.tree/2` accepts a leaf generator and a combinator that wraps subtrees into parent nodes. StreamData controls maximum depth internally and shrinks by pruning branches — so a counter-example is the smallest tree that breaks the invariant, not a randomly-sized one. Fixed-depth list-of-lists forces you to guess the problematic depth in advance and miss bugs that only appear at depth 4 or 10. Use `tree/2` whenever the domain is naturally recursive: ASTs, file-system trees, nested configs, JSON-like structures.
