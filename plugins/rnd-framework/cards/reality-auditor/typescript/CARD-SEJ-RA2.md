---
id: SEJ-RA2
role: reality-auditor
language: typescript
tags: [anomaly, skepticism, cross-check]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Default Sentry sample rates are < 1.0 for performance tracing — missing tracesSampleRate means spans are silently dropped.
specializes: [P-IMPOSSIBLE-01, R8]
---

**Good audit output:**
> `Sentry.init` sets `tracesSampleRate: 0.1` — 90% of traces are dropped. The Builder claims distributed tracing is in place. Flag: at 0.1, most transactions will not appear in Sentry Tracing. If the intent is full coverage for debugging, `tracesSampleRate: 1.0` is required (with the understanding of quota cost). If `tracesSampleRate` is absent entirely, no performance traces are captured regardless of instrumentation. Confirm the sample rate is intentional and documented.

**Worse audit output:**
> `Sentry.init` is called with a DSN. Tracing is configured.

**Why good is better:** Specializes the impossible-states principle for Sentry's sampling model. Error events and performance traces are governed by independent sample rates: `sampleRate` (errors, default 1.0) and `tracesSampleRate` (spans/transactions, default 0 — must be set explicitly). A missing or low `tracesSampleRate` means the instrumentation exists in the code but produces no data in the dashboard. Audit that the rate is explicitly set and that the team understands the tradeoff between coverage and quota consumption.
