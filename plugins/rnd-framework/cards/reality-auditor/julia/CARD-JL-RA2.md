---
id: JL-RA2
role: reality-auditor
language: julia
tags: [anomaly, skepticism, critique-evidence]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Mixed-type returns producing Union{T,Nothing} break type stability and force callers to check for nothing or face MethodError at the call site.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging the assumption that callers will reliably handle a `nothing` return — in practice most callers pattern-match on the happy path only, and the miss case silently produces a `MethodError` or `BoundsError` deep in call stack.

**Good audit output:**
> `UserStore.lookup_user/1` at `lib/user_store.jl:19` returns `user::User` on cache hit and `nothing` on miss, giving a return type of `Union{User, Nothing}`. Every downstream caller must guard against `nothing` before accessing any field on the result. Scanning the three call sites: `routes/profile.jl:34` calls `u = lookup_user(id); u.display_name` — no `nothing` check. If the user is not found, this crashes with `MethodError: no method matching getproperty(::Nothing, ::Symbol)`. The other two call sites have similar patterns. Flag: either throw a `NotFoundError` from `lookup_user/1` (making the miss path explicit and catchable) or return a typed `Result{User, NotFoundError}` wrapper, eliminating the `Union{..., Nothing}` entirely.

**Worse audit output:**
> The function returns `nothing` when the user is not found. Callers should check for this.

**Why good is better:** Saying "callers should check" is not an audit finding — it is a hope. The good output counts the actual call sites and confirms whether they do check, naming the file and line where the crash will happen. Recommending a thrown exception or a typed result type removes the problem rather than distributing the defence obligation across every future caller.
