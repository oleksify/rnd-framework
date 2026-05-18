---
id: OXY-RA2
role: reality-auditor
language: julia
tags: [anomaly, critique-evidence, defensive-programming]
applicable_task_types: [new-feature, bugfix, infra]
scope: Oxygen @cron uses Threads.@spawn with a per-second polling loop — even a once-per-minute job saturates a CPU core at 100% continuously.
specializes: [P-MEASURE-01]
---

Specializes the measure-before-optimizing principle by flagging the assumption that `@cron` is a low-overhead scheduler — its implementation polls at 1 Hz using `Threads.@spawn`, which burns a full CPU core regardless of how rarely the job fires.

**Good audit output:**
> `Scheduler.register!/0` at `lib/scheduler.jl:8` registers `@cron "*/5 * * * * *" "sync" function (); fetch_and_sync() end` to run every 5 seconds. Oxygen's `@cron` implementation spawns a task via `Threads.@spawn` that wakes every second, parses the cron expression, and checks whether the current time matches. On a single-threaded Julia process (the default unless `julia --threads N` is set), this polling loop competes with request handlers for the single OS thread, producing measurable latency spikes on the HTTP path. Even on a multi-threaded process the loop burns one hardware thread at 100% CPU with no useful work between firings. Flag: replace with `@repeat 5 "sync" function (); fetch_and_sync() end` — `@repeat` uses Julia's OS-level `Timer`, which wakes the runtime only at the scheduled interval and consumes zero CPU between firings.

**Worse audit output:**
> A cron job is registered to run every 5 seconds. The scheduling looks correct.

**Why good is better:** Whether a cron job runs at the right time is not the only correctness criterion. The good output explains the polling mechanism and its CPU cost, distinguishes single-threaded vs multi-threaded impact, and names the exact zero-overhead replacement. The worse output confuses "fires at the right time" with "is efficiently implemented".
