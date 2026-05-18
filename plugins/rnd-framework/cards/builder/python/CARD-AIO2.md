---
id: AIO2
role: builder
language: python
tags: [control-flow, error-handling, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Offload blocking calls to an executor when you must call synchronous I/O from an async context; never call blocking functions directly in a coroutine.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for async/sync boundaries: a blocking call inside a coroutine stalls the entire event loop, not just the current coroutine — use `run_in_executor` to push it off-thread when the blocking call is unavoidable.

**Good:**
```python
import asyncio
from pathlib import Path

async def read_config(path: Path) -> str:
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, path.read_text)
```

**Worse:**
```python
from pathlib import Path

async def read_config(path: Path) -> str:
    return path.read_text()   # blocks the event loop
```

**Why good is better:** Calling `path.read_text()` directly in a coroutine halts every other coroutine sharing the event loop for the duration of the disk I/O — under load this introduces latency spikes that are difficult to attribute. `run_in_executor(None, ...)` dispatches to the default `ThreadPoolExecutor` and yields control back to the event loop while the thread blocks. The preferred fix is to use an async-native library (`aiofiles`, `anyio.Path`) when available; `run_in_executor` is the correct fallback when no async alternative exists.
