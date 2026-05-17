---
id: V6
role: verifier
language: elixir
tags: [critique-evidence, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use assert_receive/2 for async message tests; assert on the message shape, not on timing.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by asserting that the message was actually received in the expected shape — not merely that some time passed during which it might have arrived.

**Good:**
```elixir
test "notifier sends a :done message after processing" do
  Notifier.process(self(), payload)
  assert_receive {:done, %{status: :ok}}, 500
end
```

**Worse:**
```elixir
test "notifier sends a :done message after processing" do
  Notifier.process(self(), payload)
  Process.sleep(100)
  assert_received :done
end
```

**Why good is better:** `assert_received/1` checks the mailbox right now — if the message hasn't arrived yet (due to scheduling), the test fails spuriously. `Process.sleep` is a guess: too short fails under load, too long slows the suite. `assert_receive/2` polls the mailbox for up to the timeout and succeeds the moment the message arrives, with no fixed sleep. It also pattern-matches the shape, so a `:done` with the wrong payload causes a clear mismatch failure.
