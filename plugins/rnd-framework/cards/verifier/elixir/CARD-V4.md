---
id: V4
role: verifier
language: elixir
tags: [critique-evidence, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Test response shape with match?/2; avoid deep field-equality assertions that overfit to incidental data.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by checking that the test assertion itself cannot silently pass for the wrong reason — it should reject any invalid shape, not just a specific incorrect value.

**Good test:**
```elixir
test "create returns a user with an id" do
  assert {:ok, %User{id: id}} = Users.create(%{email: "a@example.com"})
  assert is_binary(id)
end
```

**Worse test:**
```elixir
test "create returns a user" do
  result = Users.create(%{email: "a@example.com"})
  assert result == {:ok, %User{id: "abc123", email: "a@example.com"}}
end
```

**Why good is better:** The worse test hardcodes `id: "abc123"` — it will fail on any environment where the generated ID differs, and will pass only when the implementation happens to produce that exact struct. The good test asserts the shape (`{:ok, %User{id: id}}`) and a property of the field (`is_binary(id)`), catching wrong types and missing fields while remaining stable across runs. Verify the contract, not the incidental value.
