---
id: SVK4
role: reality-auditor
language: typescript
tags: [anomaly, cross-check, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: event.locals set in hooks.server.ts is per-request; components cannot write to it and should never be assumed to.
specializes: [P-EFFECTS-EDGE-01]
---

**Good audit output:**
> The Builder sets `event.locals.user` inside `hooks.server.ts handle()` and reads it in `+page.server.ts load()`. This is the intended pattern — `locals` is a per-request store, populated by the hook before any `load` runs. However, `+page.svelte` imports `$page` and calls `$page.data.user` — which is correct. Cross-check: is there any component that tries to set `locals` directly? If yes, that write is a no-op; `locals` is not exposed to components.

**Worse audit output:**
> The app uses `event.locals` for the authenticated user. Looks like standard SvelteKit auth.

**Why good is better:** Specializes the push-effects-to-the-edge principle for SvelteKit's request lifecycle. `event.locals` is a server-side per-request scratch space. It is populated in `hooks.server.ts` and readable in `load` functions and form actions — but it does not exist in the component layer at all. An auditor must verify that no component attempts to write to `locals` (the write is silent and lost) and that all reads come from `$page.data`, which is the correctly serialized public projection of the server data.
