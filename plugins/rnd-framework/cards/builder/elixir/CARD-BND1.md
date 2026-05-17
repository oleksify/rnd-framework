---
id: BND1
role: builder
language: elixir
tags: [configuration, boundaries, defensive-programming]
applicable_task_types: [new-feature, infra, refactor]
scope: Bandit is HTTP/2-first; explicitly enable HTTP/1.1 via http_1_options if upstream proxies or clients require it.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for Bandit's transport configuration: HTTP version negotiation happens at the protocol boundary — not declaring HTTP/1.1 support means clients that cannot negotiate HTTP/2 will fail silently or receive connection errors.

**Good:**
```elixir
# config/config.exs — explicit protocol support
config :my_app, MyAppWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [
    port: 4000,
    transport_options: [
      # Allow HTTP/1.1 for proxies and older clients that cannot negotiate HTTP/2
      http_1_options: [enabled: true]
    ]
  ]
```

**Worse:**
```elixir
# No http_1_options — relies on Bandit default; HTTP/1.1 clients may be rejected
config :my_app, MyAppWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [port: 4000]
```

**Why good is better:** Bandit defaults vary by version, and older reverse proxies (nginx < 1.9.5, AWS Classic ELB) do not support HTTP/2 — they send HTTP/1.1 to the upstream. A Bandit instance that rejects HTTP/1.1 will silently drop those connections. Explicit `http_1_options: [enabled: true]` makes the intent clear and survives Bandit default changes across upgrades. Check the Bandit README for the exact key name — it has changed between versions.
