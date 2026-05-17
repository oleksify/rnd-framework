---
id: V5
role: verifier
language: elixir
tags: [error-handling, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use ExUnit.Callbacks.on_exit/1 for resource cleanup so teardown runs even when a test crashes.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by ensuring cleanup effects (closing connections, stopping processes) are registered at test boundary entry, not deferred to a later teardown that may never run.

**Good:**
```elixir
setup do
  {:ok, conn} = MyDB.connect()
  on_exit(fn -> MyDB.disconnect(conn) end)
  {:ok, conn: conn}
end
```

**Worse:**
```elixir
setup do
  {:ok, conn} = MyDB.connect()
  {:ok, conn: conn}
end

# somewhere in the test body or a separate on_exit registered after potential failure
```

**Why good is better:** If `on_exit` is registered inside a test body or after a step that might fail, the cleanup callback is never registered and resources leak. Registering `on_exit` immediately after acquiring the resource — inside `setup` — guarantees teardown runs even when the test itself raises. ExUnit calls `on_exit` callbacks after each test regardless of outcome. Cleanup belongs at the boundary where the resource is acquired.
