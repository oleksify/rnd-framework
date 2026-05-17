---
id: SVK5
role: reality-auditor
language: typescript
tags: [anomaly, skepticism, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Form actions must return ActionResult or throw redirect/error; raw Response or unhandled throws bypass the SvelteKit error boundary.
specializes: [P-IMPOSSIBLE-01]
---

**Good audit output:**
> The form action calls `return fail(422, { errors })` on validation failure and `redirect(303, '/dashboard')` on success. Both are SvelteKit-recognized `ActionResult` shapes — the client receives typed `form` data and `enhance` handles the response without a full page reload. The flow is auditable and the error path is visible in the component via `export let form`.

**Worse audit output:**
> The action calls `return new Response(JSON.stringify({ error: 'invalid' }), { status: 422 })`. SvelteKit's form enhancement (`use:enhance`) does not recognize a raw `Response` as an `ActionResult` — it will treat it as an unexpected response, potentially causing the form to fall back to a full page reload or silently dropping the error data. Flag: replace with `return fail(422, { error: 'invalid' })`.

**Why good is better:** Specializes the impossible-states principle for SvelteKit form actions. The `ActionResult` union (`success`, `failure`, `redirect`, `error`) is the only type that `use:enhance` knows how to dispatch — raw `Response` objects and unhandled throws bypass the enhancement lifecycle entirely. An auditor must verify that every exit path from a form action uses a SvelteKit action helper (`fail`, `redirect`, `error`) rather than constructing raw responses, which creates a silent protocol mismatch between server and client.
