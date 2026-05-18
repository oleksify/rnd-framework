---
id: OXY2
role: builder
language: julia
tags: [scope, defensive-programming]
applicable_task_types: [new-feature, refactor]
scope: Use `@repeat` for interval-based background jobs in Oxygen, not `@cron` with short intervals.
specializes: [P-MEASURE-01]
---

Specializes the measurement principle by choosing a scheduler whose resource cost is proportional to its work. `@cron` uses `Threads.@spawn` with a per-second polling loop that runs regardless of whether work is due; `@repeat` delegates timing to an OS `Timer` and consumes no CPU between firings.

**Good:**
```julia
# Fires every 60 seconds — zero CPU between runs
@repeat 60 "collect-metrics" function ()
    record_metrics()
end
```

**Worse:**
```julia
# Polls every second to check whether a minute has elapsed — 100% CPU on single-threaded Julia
@cron "*/1 * * * *" "collect-metrics" function ()
    record_metrics()
end
```

**Why good is better:** `@cron` spawns a thread that loops with a one-second sleep, polling the clock on every iteration. On single-threaded Julia this saturates the scheduler thread. `@repeat` registers a `Timer` callback in the OS event loop — the runtime thread sleeps until the interval elapses and is woken by the OS. For any job whose period is expressible as a fixed interval, `@repeat` is strictly cheaper. Reserve `@cron` for calendar-based schedules (e.g., "every weekday at 09:00") that a fixed interval cannot express.
