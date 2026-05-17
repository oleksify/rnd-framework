---
id: SES-RA1
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, configuration]
applicable_task_types: [new-feature, bugfix, refactor, infra]
scope: Audit Sentry before_send configuration — a custom callback can silently drop events; verify the callback's return contract in staging before assuming events reach Sentry.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging that a `:before_send` callback returning `nil` (or any non-map value) silently suppresses the event — the SDK emits nothing and logs nothing by default.

**Good audit output:**
> `config/config.exs` configures `before_send: {MyApp.SentryFilter, :filter_event}`. Inspected `lib/my_app/sentry_filter.ex`: the function matches on `event.exception` type to redact PII fields and returns `nil` for `Ecto.NoResultsError`. Returning `nil` from `:before_send` drops the event — Sentry receives nothing, there is no log line, and the dropped event is not counted in the Sentry dashboard. This is intentional for `NoResultsError`, but the catch-all clause also returns `nil` for any unmatched exception. Flag: the catch-all should return the event unchanged, not `nil`; otherwise new exception types are silently suppressed until someone notices missing alerts. Ref: https://hexdocs.pm/sentry/Sentry.html#module-configuration

**Worse audit output:**
> The Sentry configuration includes a before_send callback. This is a valid way to filter events.

**Why good is better:** The worse output confirms the callback exists without checking its return paths. A `before_send` function that returns `nil` for unhandled clauses is a silent event drain that operators only discover when expected alerts don't arrive. The good output traces the return path for the catch-all clause and names the consequence — dropped events with no observable signal.
