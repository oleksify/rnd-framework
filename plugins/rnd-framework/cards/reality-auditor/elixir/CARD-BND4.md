---
id: BND4
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, inconsistency]
applicable_task_types: [new-feature, bugfix, infra]
scope: WebSocket upgrades under Bandit require the Phoenix.Socket or a WebSock-compatible handler; Plug.Conn alone cannot carry the upgrade — code that tries will silently fall back to HTTP.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by flagging the boundary between HTTP and WebSocket: the upgrade is an explicit protocol handoff, not an implicit conn transformation, and missing the right adapter means clients connect but never upgrade.

**Good audit output:**
> `MyAppWeb.UserSocket` at `lib/web/user_socket.ex` is declared with `use Phoenix.Socket`. The Phoenix endpoint at `lib/web/endpoint.ex:12` includes `socket "/socket", MyAppWeb.UserSocket, websocket: true, longpoll: false`. Bandit is configured as the adapter. Verified: Phoenix's WebSocket transport implements the `WebSock` behaviour that Bandit requires for protocol upgrade. Client connections to `/socket/websocket` will upgrade correctly. No anomaly.
>
> Counter-check: `StreamHandler` at `lib/web/plugs/stream_handler.ex` calls `Plug.Conn.upgrade_adapter(conn, :websocket, handler)` directly with a custom module that does not implement `WebSock`. Under Bandit, this will raise at runtime — Bandit requires `WebSock` compliance, not arbitrary upgrade adapters. Flag: implement the `WebSock` behaviour or delegate to a Phoenix channel.

**Worse audit output:**
> The application uses Phoenix sockets for WebSocket connections. The endpoint config looks correct.

**Why good is better:** Phoenix channels handle the `WebSock` compliance transparently, but custom `Plug.Conn.upgrade_adapter/3` calls do not — they must explicitly implement `WebSock`. The good output distinguishes the two upgrade paths and checks which behaviour contract each handler satisfies, rather than assuming that "uses Phoenix" means all WebSocket paths are compliant.
