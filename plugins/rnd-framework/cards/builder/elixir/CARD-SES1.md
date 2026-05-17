---
id: SES1
role: builder
language: elixir
tags: [error-handling, control-flow, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Wrap rescue blocks with Sentry.capture_exception/2 then reraise — never reraise inside the capture call.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by keeping the Sentry side effect (capture) at the boundary — separate from, and before, the reraise — so both the report and the stack propagation are unambiguous.

**Good:**
```elixir
def process(order) do
  do_process(order)
rescue
  e ->
    Sentry.capture_exception(e, stacktrace: __STACKTRACE__)
    reraise e, __STACKTRACE__
end
```

**Worse:**
```elixir
def process(order) do
  do_process(order)
rescue
  e ->
    reraise Sentry.capture_exception(e), __STACKTRACE__
    # capture_exception returns {:ok, id} | :error — reraising that is a second exception
end
```

**Why good is better:** `Sentry.capture_exception/2` is fire-and-forget — it returns `{:ok, id}` or `:error`, not the original exception. Passing its return value to `reraise` raises a new `FunctionClauseError` on the wrong return shape, shadowing the original error and producing a confusing crash. Capture first, reraise separately, always pass `__STACKTRACE__` to both so Sentry and the crash report share the same frames. Ref: https://hexdocs.pm/sentry/Sentry.html#capture_exception/2
