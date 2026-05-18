---
id: OXY-RA3
role: reality-auditor
language: julia
tags: [anomaly, skepticism, defensive-programming]
applicable_task_types: [new-feature, bugfix, infra]
scope: Oxygen staticfiles eagerly reads the target directory at registration time — if the directory does not exist the server crashes before accepting any request.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the side-effect edge-case principle by flagging the assumption that `staticfiles` is safe to call unconditionally — Oxygen reads and indexes the directory during `staticfiles()` registration, so a missing directory crashes the server process at startup, not at the first request.

**Good audit output:**
> `Application.start/0` at `src/app.jl:24` calls `staticfiles("public", "/static")`. The `public/` directory is produced by a separate frontend build step (`npm run build`). In a fresh checkout, in CI before the frontend build runs, or on first deployment before assets are compiled, `public/` does not exist. Oxygen calls `readdir("public")` inside `staticfiles()` during server registration — if the directory is absent, the call throws `SystemError: readdir("public"): No such file or directory` and the server exits before binding to any port. Flag: guard the call with `isdir("public") && staticfiles("public", "/static")` so the server starts cleanly even without built assets. Alternatively, replace with `dynamicfiles("public", "/static")`, which re-reads the directory on each request and tolerates the directory appearing after startup.

**Worse audit output:**
> The server registers a static file handler for the public directory.

**Why good is better:** The good output names the exact condition that causes the crash (missing directory), identifies the specific call inside Oxygen that does the eager read, and gives two concrete remedies with different tradeoffs. The worse output merely confirms what the code does without checking whether the directory is guaranteed to exist at the time the code runs.
