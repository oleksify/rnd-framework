---
id: AIO1
role: builder
language: python
tags: [error-handling, control-flow, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use asyncio.TaskGroup for concurrent tasks when partial failure should cancel siblings; prefer gather only when you need independent-failure semantics.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for asyncio concurrency: TaskGroup (Python 3.11+) is the structured-concurrency primitive — partial failure propagates cleanly and cancels remaining siblings automatically.

**Good:**
```python
import asyncio

async def fetch_all(urls: list[str]) -> list[str]:
    results = []
    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(fetch(url)) for url in urls]
    return [t.result() for t in tasks]
```

**Worse:**
```python
import asyncio

async def fetch_all(urls: list[str]) -> list[str]:
    tasks = [asyncio.create_task(fetch(url)) for url in urls]
    return list(await asyncio.gather(*tasks))
```

**Why good is better:** When one task in a `TaskGroup` raises, the group cancels all sibling tasks and re-raises as an `ExceptionGroup`, so no coroutine leaks and the caller always sees the failure. `gather` silently keeps other tasks running by default; with `return_exceptions=True` you must manually inspect every result for exceptions, and with the default `return_exceptions=False` a single failure cancels gather's awaitable but orphans already-started tasks. `gather` remains appropriate for older codebases (pre-3.11) or when truly independent failure semantics are desired — prefer TaskGroup for new code that needs structured concurrency.
