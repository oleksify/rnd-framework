---
id: SEJ-RA1
role: reality-auditor
language: typescript
tags: [anomaly, skepticism, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Sentry beforeSend returning null silently drops events — verify the filter in staging before treating observability as complete.
specializes: [P-IMPOSSIBLE-01, R9]
---

**Good audit output:**
> `Sentry.init` includes a `beforeSend` hook that returns `null` for errors whose `message` matches a user-facing denylist. The Builder claims "low-signal errors are filtered." Flag: if the regex is too broad or applied to the wrong field, production errors will be silently dropped — no alert, no trace, no indication the filter fired. Verify the filter in a staging environment by deliberately triggering a known error and confirming it appears in Sentry before shipping.

**Worse audit output:**
> `beforeSend` is configured to filter noise. The Sentry SDK is set up correctly.

**Why good is better:** Specializes the impossible-states principle for Sentry's event pipeline. `beforeSend` returning `null` is an unconditional drop — the SDK does not log, counter, or surface filtered events in any other way. A misconfigured filter (wrong field, wrong regex, overly broad pattern) silently eliminates observability for an entire error class. The audit must require staging evidence that the filter fires only on intended events, not just that the hook exists.
