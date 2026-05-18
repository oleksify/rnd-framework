---
id: B6
role: builder
language: python
tags: [configuration, premature-abstraction]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Named constants suffice until a real second use case justifies a config object.
specializes: [P-SMALL-MODULES-01]
---

**Good:**
```python
RETRY_ATTEMPTS = 3
RETRY_BACKOFF_SECONDS = 1.0

def fetch(url: str) -> Response:
    for attempt in range(RETRY_ATTEMPTS):
        try:
            return http_client.get(url, timeout=10)
        except TimeoutError:
            if attempt == RETRY_ATTEMPTS - 1:
                raise
            time.sleep(RETRY_BACKOFF_SECONDS * (2 ** attempt))
```

**Worse:**
```python
@dataclass
class FetchConfig:
    retry_attempts: int = 3
    retry_backoff_seconds: float = 1.0
    timeout_seconds: int = 10
    backoff_multiplier: float = 2.0
    use_exponential_backoff: bool = True

def fetch(url: str, config: FetchConfig = FetchConfig()) -> Response: ...
```

**Why good is better:** The config object advertises flexibility we have no caller for. Named constants at the top of the file are sufficient until a real second use case shows up. When it does, refactor *then* — with knowledge of the actual second case rather than guesses about it.
