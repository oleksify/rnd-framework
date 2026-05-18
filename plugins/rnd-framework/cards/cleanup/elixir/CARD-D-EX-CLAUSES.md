---
id: D-EX-CLAUSES
role: cleanup
language: elixir
tags: [dead-code, commented-out]
applicable_task_types: [refactor]
scope: Delete commented-out match clauses in case and with blocks rather than leaving them as a ghost roadmap.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```elixir
def handle_result(result) do
  case result do
    {:ok, value} ->
      process(value)
    # {:ok, %{legacy: true} = value} ->
    #   legacy_process(value)
    {:error, :not_found} ->
      {:error, "not found"}
    # {:error, :timeout} ->
    #   {:error, "timed out"}
    _ ->
      {:error, "unexpected"}
  end
end
```

**After:**
```elixir
def handle_result(result) do
  case result do
    {:ok, value} ->
      process(value)
    {:error, :not_found} ->
      {:error, "not found"}
    _ ->
      {:error, "unexpected"}
  end
end
```

**Why after is better:** Commented-out match clauses are worse than dead code — they imply the clause might be needed again, suggest the codebase still deals with that shape of data, and mislead anyone reading the exhaustiveness of the pattern match. If `{:error, :timeout}` is a real concern, handle it explicitly; if it is not, its comment is noise. Git preserves the history; the file should only show what is currently true.
