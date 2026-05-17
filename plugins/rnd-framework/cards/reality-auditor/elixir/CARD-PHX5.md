---
id: PHX5
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, inconsistency]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Conn assigns are nil until the plug that sets them has run; verify plug pipeline order before assuming an assign is present.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging the assumption that a conn assign exists — an assumption that is false if the setting plug runs after the code that reads it, or is not in the pipeline at all.

**Good audit output:**
> `AdminController.index/2` at `lib/web/controllers/admin_controller.ex:8` reads `conn.assigns.current_user` directly (no `Map.get` guard). Traced the plug pipeline in `router.ex`: the `:browser` pipeline applies `plug MyApp.Auth.RequireUser` at line 23. `AdminController` is mounted under the `:admin` scope, which uses only the `:browser` pipeline — `RequireUser` runs before the action. Assign is guaranteed present. No anomaly.
>
> Counter-check: `ReportController` at line 41 is mounted directly under `scope "/"`, which uses only the `:api` pipeline — `RequireUser` is absent. `conn.assigns.current_user` at `report_controller.ex:6` will be nil. Flag: this is a missing plug, not a guarded access.

**Worse audit output:**
> The controller reads `conn.assigns.current_user`. This is set by the authentication plug in the pipeline.

**Why good is better:** An assign set by a plug only exists if that plug is in the pipeline upstream of the action. The good output traces the router scope and pipeline for each controller, not just the one under review. The worse output assumes the plug is present without checking which pipeline the controller's router scope uses.
