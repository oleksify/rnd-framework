---
id: OXY-RA1
role: reality-auditor
language: julia
tags: [anomaly, skepticism, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Oxygen route syntax /{path...} creates Symbol("path...") as the parameter name — the handler receives Symbol("path"), which never matches, silently returning 404.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging the assumption that Oxygen supports Phoenix-style `{path...}` wildcard segments — Oxygen uses HTTP.jl router conventions where `{path...}` is treated as a literal parameter name including the trailing `...`, so no segment ever binds.

**Good audit output:**
> `FileRouter.register!/0` at `lib/file_router.jl:12` registers `@get "/files/{path...}" function (req, path); serve_file(path) end`. Oxygen passes HTTP.jl router parameters as keyword arguments keyed by their `Symbol` name. The segment `{path...}` produces `Symbol("path...")` as the key, but the function parameter `path` is bound to `Symbol("path")` — these never match. Every request to `/files/anything` returns a 404 with no error logged. Flag: replace `{path...}` with `/*` for a single-segment path, or `/*/*` for two-segment paths. If arbitrary depth is required, use a catch-all middleware rather than a route parameter.

**Worse audit output:**
> The route uses `{path...}` for a wildcard segment. This should capture the remaining path.

**Why good is better:** `{path...}` looks like wildcard capture syntax borrowed from Phoenix or FastAPI, but Oxygen does not define that convention. The good output names the exact symbol mismatch (`Symbol("path...")` vs `Symbol("path")`), explains the observable symptom (silent 404), and gives concrete replacement patterns. The worse output assumes the syntax works without checking Oxygen's actual routing model.
