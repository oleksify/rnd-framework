---
id: PHX4
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Phoenix.LiveView.connected?/1 returns false during the initial static render; code that branches on it must be correct in both states.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by flagging the LiveView two-phase render: the static HTTP render always sees `connected? == false`, and code that skips setup in that branch must still produce a valid initial state.

**Good audit output:**
> `UserDashboard.mount/3` at `lib/web/live/dashboard_live.ex:14` calls `if connected?(socket), do: Metrics.subscribe()`. The subscription is correctly gated — no subscription fires on the static render, preventing double-subscribes. Verify: the socket still has valid `assigns.metrics` after mount when `connected?` is false. If `assigns.metrics` is set only inside the `connected?` branch, the static render will crash in the template with an assign-missing error. Checked: `assign(socket, metrics: [])` appears before the gate — correct. No anomaly.

**Worse audit output:**
> The LiveView uses `connected?/1` to conditionally subscribe to metrics. This is the standard LiveView pattern.

**Why good is better:** Every LiveView mount runs twice: once as a static HTTP render (`connected? == false`) and once after the WebSocket upgrade (`connected? == true`). Code that moves assigns inside the `connected?` guard produces an undefined assign during the first render. The good output traces whether the assigns are initialized outside the guard and confirms the static render is safe — not just that the pattern looks familiar.
