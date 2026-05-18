---
id: JL5
role: builder
language: julia
tags: [defensive-programming, control-flow]
applicable_task_types: [new-feature, bugfix]
scope: Build the HTTP response body as a String first; never use a do-block with HTTP.Response.
---

Julia's `do`-block syntax passes the block as the **first positional argument**, not as the body. `HTTP.Response(status, headers) do io ... end` produces a function as the first argument, silently corrupting the constructor call instead of writing a body.

**Good:**
```julia
function json_response(data)
    body = JSON3.write(data)
    HTTP.Response(200, ["Content-Type" => "application/json"], body)
end
```

**Worse:**
```julia
function json_response(data)
    HTTP.Response(200, ["Content-Type" => "application/json"]) do io
        JSON3.write(io, data)     # do-block becomes first arg, not body
    end
end
```

**Why good is better:** In the worse version Julia desugars the `do` block to `HTTP.Response(io -> JSON3.write(io, data), 200, headers)` — the lambda lands in the `status` slot and the constructor either throws a confusing `MethodError` or silently creates a malformed Response. Build the body string up-front; the three-argument constructor `Response(status, headers, body)` is unambiguous and always correct.
