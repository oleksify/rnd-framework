---
id: D-EX-DEBUG
role: cleanup
language: elixir
tags: [dead-code, debugging]
applicable_task_types: [refactor]
scope: Remove Logger.debug and IO.inspect calls added for temporary troubleshooting rather than production observability.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```elixir
def process_payment(attrs) do
  IO.inspect(attrs, label: "process_payment attrs")
  changeset = Payment.changeset(%Payment{}, attrs)
  IO.inspect(changeset, label: "changeset")
  Logger.debug("Inserting payment: #{inspect(attrs)}")
  Repo.insert(changeset)
end
```

**After:**
```elixir
def process_payment(attrs) do
  changeset = Payment.changeset(%Payment{}, attrs)
  Repo.insert(changeset)
end
```

**Why after is better:** `IO.inspect` is a REPL aid — it always writes to stdout regardless of log level, environment, or release configuration. In production it pollutes standard output with raw struct dumps that may contain sensitive fields. `Logger.debug` calls added for troubleshooting (not structured observability) should be removed once the bug is resolved; they add noise at `:debug` level and often interpolate large terms that waste memory on string building even when the log level suppresses output. Delete both unconditionally if they were not part of the original intentional logging design.
