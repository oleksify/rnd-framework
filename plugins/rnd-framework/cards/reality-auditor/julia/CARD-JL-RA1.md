---
id: JL-RA1
role: reality-auditor
language: julia
tags: [anomaly, skepticism, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Float64(x) has no method for String — bare coercion on API response fields crashes on inconsistent payloads.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by flagging the assumption that an external API always returns numeric fields as JSON numbers — an assumption that breaks silently until a payload arrives with the value encoded as a string.

**Good audit output:**
> `LunchMoneyClient.fetch_transactions/1` at `lib/lunch_money_client.jl:42` calls `Float64(txn["amount"])` directly. External APIs commonly return numeric fields as either JSON numbers or strings depending on the endpoint version, locale, or edge-case zero values. When `txn["amount"]` is `"12.50"` (a String), Julia throws `MethodError: no method matching Float64(::String)` and the request handler crashes. The caller receives a 500 with no indication of which field or payload triggered the failure. Flag: replace `Float64(txn["amount"])` with a multi-dispatch helper — `_to_float(x::Number) = Float64(x)` / `_to_float(x::AbstractString) = parse(Float64, x)` — and call `_to_float(txn["amount"])` throughout the client.

**Worse audit output:**
> The code converts API response fields to Float64. This looks standard.

**Why good is better:** `Float64(x)` when `x` is already a `Float64` is fine — but the method does not exist for `String`. An API returning `"amount": "0"` on a zero-balance transaction will crash code that was tested only against numeric payloads. The good output names the exact method error, identifies which value triggers it, and prescribes the multi-dispatch fix rather than a conditional type-check.
