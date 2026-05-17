---
id: R4
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, inconsistency]
applicable_task_types: [new-feature, bugfix, refactor, infra]
scope: Mix.env/0 is a compile-time macro; code that calls it at runtime silently locks the value from build time.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle by flagging a class of runtime checks that appear to be dynamic but are actually frozen at compile time.

**Good audit output:**
> `Config.dev_mode?/0` at `lib/config.ex:12` calls `Mix.env() == :dev`. This is a compile-time macro call — in a release build, `Mix.env()` is `:prod` regardless of how the app is started. If this function is intended to gate a runtime feature flag, the value is baked into the release binary and cannot change without a recompile. Flag: this is probably wrong — use `Application.get_env/3` with a runtime config instead.

**Worse audit output:**
> The code checks `Mix.env()` to determine the environment. This is a valid Elixir pattern.

**Why good is better:** `Mix.env()` returns the environment *at compile time*, not at the time the function is called. A release compiled with `MIX_ENV=prod` will return `:prod` from `Mix.env()` forever, ignoring any `MIX_ENV` value set at runtime. The good output names the file, explains the mechanism, and distinguishes the intent ("runtime gate") from what actually happens. Runtime config belongs in `Application.get_env/3` with `config/runtime.exs`.
