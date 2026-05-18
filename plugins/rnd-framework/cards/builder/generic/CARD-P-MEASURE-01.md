---
id: P-MEASURE-01
role: builder
language: generic
tags: [tooling, verifiability, critique-evidence]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Gather tool-grade evidence of a bottleneck before changing code for performance reasons.
---

Measure before optimizing — performance changes require profiler or benchmark evidence, never intuition.

**Good:**
```python
# cProfile shows db.get_user() accounts for 94% of request time
# Confirmed with pytest-benchmark: 12ms baseline, 1.1ms after index added

def get_user_profile(user_id: int) -> Profile:
    user = db.get_user(user_id)   # was 12ms; now 1.1ms
    return build_profile(user)
```

**Worse:**
```python
# "DB calls feel slow" — switched to a manual cache dict

_cache: dict[int, User] = {}

def get_user_profile(user_id: int) -> Profile:
    if user_id not in _cache:
        _cache[user_id] = db.get_user(user_id)
    return build_profile(_cache[user_id])
```

**Why good is better:** The worse version adds a process-lifetime cache based on intuition, creating a stale-data bug and unbounded memory growth without evidence that the DB call is the bottleneck. The good version starts from a profiler trace that names the exact function and its cost, then validates the fix with a benchmark. Any performance change made without `EXPLAIN ANALYZE`, `cProfile`, `pytest-benchmark`, or equivalent tool output is speculation — it may introduce a new bug to solve a problem that did not exist.
