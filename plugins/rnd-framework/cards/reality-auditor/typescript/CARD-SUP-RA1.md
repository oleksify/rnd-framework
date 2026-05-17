---
id: SUP-RA1
role: reality-auditor
language: typescript
tags: [anomaly, skepticism, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Supabase Realtime channels accumulate per hot-reload cycle unless explicitly unsubscribed — audit that cleanup is called.
specializes: [P-EFFECTS-EDGE-01, R10]
---

**Good audit output:**
> The Builder subscribes to a Realtime channel inside a React `useEffect` and returns a cleanup function that calls `channel.unsubscribe()` and `supabase.removeChannel(channel)`. On HMR, the effect re-runs: old channel is unsubscribed before the new one is created. No leak.

**Worse audit output:**
> The component subscribes to a Realtime channel inside `useEffect` with the correct event filter. Looks complete.

**Why good is better:** Specializes the push-effects-to-the-edge principle for Supabase Realtime lifecycle. Every `supabase.channel()` call opens a WebSocket subscription that persists until explicitly removed — React HMR and StrictMode double-invoke effects, so a missing cleanup function multiplies open connections each reload. The audit must verify that `channel.unsubscribe()` and `supabase.removeChannel()` appear in the effect's return value (or equivalent teardown), not merely that the subscription is created.
