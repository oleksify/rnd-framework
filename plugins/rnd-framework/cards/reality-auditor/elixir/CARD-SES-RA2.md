---
id: SES-RA2
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, configuration]
applicable_task_types: [new-feature, bugfix, refactor, infra]
scope: Audit Sentry DSN handling — the DSN is a URL containing a secret key; never log it, never include it in crash reports, never URL-decode it into plain text in application code.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by treating DSN logging as a side effect that leaks credentials — the DSN must stay confined to the Sentry SDK configuration boundary.

**Good audit output:**
> `config/runtime.exs` sets `config :sentry, dsn: System.get_env("SENTRY_DSN")`. Searched for `SENTRY_DSN`, `sentry_dsn`, and `dsn` across `lib/` and `test/`: no log calls, no `IO.inspect`, no string interpolation with the DSN value. The value flows only into `:sentry` application config, which the SDK reads at startup. No exposure found.

**Worse audit output:**
> The DSN is read from an environment variable. This is the correct approach.

**Why good is better:** The Sentry DSN format is `https://<key>@<host>/<project-id>`. The `<key>` segment is a secret token — anyone with it can submit events to your Sentry project, ingest arbitrary data, and consume your event quota. The worse output confirms the env-var pattern without checking whether the value is ever logged or interpolated downstream. The good output shows the grep scope (lib + test), the log-call patterns searched, and the result — proving the DSN stays within the SDK boundary. Ref: https://docs.sentry.io/platforms/elixir/
