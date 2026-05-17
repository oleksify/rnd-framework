---
id: SES2
role: builder
language: elixir
tags: [boundaries, control-flow, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Set Sentry.Context per process at the request boundary — never globally; context is process-local.
specializes: [P-EFFECTS-EDGE-01, B7]
---

Specializes the effects-at-the-edge principle by placing the Sentry context mutation at the outermost process boundary — the plug, GenServer callback, or job worker — so downstream code reads a populated context without needing to know about Sentry.

**Good:**
```elixir
defmodule MyAppWeb.SentryContextPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      nil  -> conn
      user ->
        Sentry.Context.set_user_context(%{id: user.id, email: user.email})
        conn
    end
  end
end
```

**Worse:**
```elixir
# In application.ex or a module attribute — runs once in a shared process
Sentry.Context.set_user_context(%{id: :system, email: "system@example.com"})

# Or called from a library helper without knowing the current request
def tag_sentry(user_id) do
  Sentry.Context.set_user_context(%{id: user_id})   # wrong process? no-op
end
```

**Why good is better:** `Sentry.Context` stores data in the calling process's dictionary — every request process starts with a blank slate. Setting context in `Application.start/2` or a shared GenServer writes to the wrong process and has no effect on request workers. Setting it in a Plug at the top of the pipeline guarantees it is present for every error captured downstream in the same request process. Ref: https://hexdocs.pm/sentry/Sentry.Context.html
