---
id: JL-RA4
role: reality-auditor
language: julia
tags: [anomaly, skepticism, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: HTTP.Response do-block syntax passes the block as the first positional argument, not as the body — the intended three-argument constructor is never called.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging the assumption that Julia's `do`-block syntax threads the block as the last or "body" argument — in fact Julia always passes the `do` block as the FIRST positional argument, which does not match any `HTTP.Response` constructor signature.

**Good audit output:**
> `WebServer.send_report/2` at `lib/web_server.jl:61` constructs an HTTP response as `HTTP.Response(200, headers) do io; write(io, body_str) end`. Julia's `do`-block syntax desugars this to `HTTP.Response(io -> write(io, body_str), 200, headers)`, passing the anonymous function as the first argument. `HTTP.Response` has no constructor accepting `(::Function, ::Int, ::Vector)` — this call either throws `MethodError` at runtime or, if an unrelated method happens to match, silently constructs the wrong response. The fix is to build the body string first and pass it directly: `HTTP.Response(200, headers, body_str)`.

**Worse audit output:**
> The code builds an HTTP response using a do-block. This is idiomatic Julia.

**Why good is better:** `do`-block syntax is idiomatic — for functions that accept a callback as their first argument. `HTTP.Response` is a plain struct constructor, not a higher-order function. The good output states exactly what the desugaring produces, names the non-existent constructor signature, and gives the correct fix. The worse output endorses the pattern as idiomatic without checking whether the target function's signature is compatible.
