---
id: ECT2
role: builder
language: elixir
tags: [control-flow, defensive-programming, abstraction]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Preload associations in the query, not lazily after the fact; every lazy Repo.preload inside a loop is an N+1.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by pushing the association load to the query boundary rather than deferring it into iteration, preventing the N+1 query pattern that is invisible at call sites but catastrophic under load.

**Good:**
```elixir
# One query: posts + all authors in two SQL statements
def list_posts_with_authors do
  Post
  |> Repo.all()
  |> Repo.preload(:author)
end
```

**Worse:**
```elixir
# N+1: one query per post to fetch its author
def list_posts_with_authors do
  posts = Repo.all(Post)
  Enum.map(posts, fn post ->
    author = Repo.preload(post, :author).author
    %{post | author: author}
  end)
end
```

**Why good is better:** `Repo.preload/2` outside a loop issues one batched query for all association IDs — two SQL statements total regardless of post count. `Repo.preload` inside `Enum.map` issues one query per post: 100 posts = 101 queries. The fix is not a different function — it is where you call the same function. Prefer `Repo.all(from p in Post, preload: [:author])` when the relationship is always needed, or batch-preload at the boundary when it is conditional.
