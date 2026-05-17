---
id: R10
role: reality-auditor
language: typescript
tags: [anomaly, error-handling, cross-check]
applicable_task_types: [new-feature, bugfix, refactor]
scope: fetch only rejects on network failure; HTTP 4xx/5xx responses resolve normally unless response.ok is checked.
specializes: [P-EFFECTS-EDGE-01]
---

**Good audit output:**
> `await fetch('/api/submit')` is called without checking `response.ok`. A 400 or 500 response will resolve — not reject — so the `catch` block will not fire on server errors. The code then calls `response.json()` unconditionally; on a 404 that returns HTML, this will throw a parse error unrelated to the actual failure. Flag: missing `response.ok` guard.

**Worse audit output:**
> The fetch call is wrapped in a try/catch, so errors are handled. The response is parsed and used correctly.

**Why good is better:** Specializes the push-effects-to-the-edge principle for the `fetch` API's non-obvious error model. Unlike `XMLHttpRequest` error callbacks, `fetch` only rejects its `Promise` on network-level failures (DNS, timeout, CORS). HTTP error status codes are surfaced as resolved responses with `response.ok === false`. An auditor who sees a `try/catch` and concludes "errors handled" has missed the actual failure path — only a `response.ok` check or equivalent status inspection closes the gap.
