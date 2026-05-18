---
id: OXY-V1
role: verifier
language: julia
tags: [critique-evidence, validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Test Oxygen route handlers via HTTP.request to a live local server, not by calling the handler function directly.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle: Oxygen's router, middleware, and JSON body parsing are the boundary where most regressions occur — calling the inner handler function directly bypasses all of that and produces false confidence.

**Good:**
```julia
using Test, HTTP, JSON3, Oxygen

function setup_server()
    @get "/users/{id}" function(req, id::Int)
        json(Dict("id" => id, "name" => "Alice"))
    end
    serveparallel(port=8081; async=true)
end

@testset "GET /users/:id" begin
    server = setup_server()
    try
        resp = HTTP.get("http://localhost:8081/users/42")
        @test resp.status == 200
        body = JSON3.read(resp.body)
        @test body[:id] == 42
    finally
        close(server)
    end
end
```

**Worse:**
```julia
@testset "user route handler" begin
    req = HTTP.Request("GET", "/users/42")
    resp = route_handler(req, 42)
    @test resp.status == 200
end
```

**Why good is better:** Constructing a bare `HTTP.Request` and calling the handler directly skips Oxygen's router (which binds path parameters), its middleware stack (CORS, JSON body parsing, error recovery), and the HTTP serialization round-trip. Tests that pass this way regularly fail in production when the middleware chain rejects a malformed request or the router cannot bind a parameter. Start a real `serveparallel` instance (async mode, fixed port) and make actual HTTP calls — this is the only form that tests what users actually hit.
