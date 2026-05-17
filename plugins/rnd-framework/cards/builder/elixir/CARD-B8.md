---
id: B8
role: builder
language: elixir
tags: [validation, boundaries, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use @enforce_keys to make required struct fields impossible to omit at construction time.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by encoding required fields at the struct level so the compiler rejects construction without them.

**Good:**
```elixir
defmodule User do
  @enforce_keys [:id, :email]
  defstruct [:id, :email, :name]
end

# Compile-time error — :id and :email are required
%User{name: "Alice"}
```

**Worse:**
```elixir
defmodule User do
  defstruct [:id, :email, :name]
end

# Silently creates %User{id: nil, email: nil, name: "Alice"}
%User{name: "Alice"}
```

**Why good is better:** Without `@enforce_keys`, a struct can be built with `nil` identity fields that look valid until something downstream dereferences them. With `@enforce_keys [:id, :email]`, any construction that omits those keys raises at the call site — a compile-time guarantee that callers cannot skip. Use it for fields whose absence would be a programming error, not a valid runtime condition.
