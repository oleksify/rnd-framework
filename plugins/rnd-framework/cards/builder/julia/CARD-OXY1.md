---
id: OXY1
role: builder
language: julia
tags: [boundaries, defensive-programming]
applicable_task_types: [new-feature, bugfix]
scope: Use Oxygen glob syntax `/*` for path parameters, not Phoenix-style `/{name...}` capture groups.
---

Oxygen routes HTTP.jl's router, which uses `/*` globs — not Phoenix/Plug-style `{path...}` named captures. Using `{path...}` creates a `Symbol("path...")` parameter that never binds the captured segment.

**Good:**
```julia
# Single-segment wildcard: matches /files/report.pdf
@get "/files/*" function (req)
    path = HTTP.URI(req.target).path
    filename = last(split(path, "/"))
    serve_file(filename)
end

# Two-segment wildcard: matches /files/2024/report.pdf
@get "/files/*/*" function (req)
    parts = filter(!isempty, split(HTTP.URI(req.target).path, "/"))
    serve_file(parts[2], parts[3])
end
```

**Worse:**
```julia
# {path...} is not Oxygen syntax — the parameter is never bound
@get "/files/{path...}" function (req, path)
    serve_file(path)   # path is always missing or Symbol("path...")
end
```

**Why good is better:** Oxygen's path router is HTTP.jl's `Router`, which uses glob segments (`*`) not named captures. The `{path...}` syntax compiles without error but creates a `Symbol("path...")` slot that does not receive the actual URL segment, so `path` arrives as `nothing` or causes a `MethodError`. Parse the raw `req.target` string directly with `HTTP.URI` to extract segments reliably.
