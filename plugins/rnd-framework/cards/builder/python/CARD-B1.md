---
id: B1
role: builder
language: python
tags: [error-handling, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Handle errors at the layer that can act on them, not the layer that observed them.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```python
def parse_timestamp(s: str) -> datetime:
    return datetime.fromisoformat(s)
```

**Worse:**
```python
def parse_timestamp(s: str) -> datetime | None:
    try:
        return datetime.fromisoformat(s)
    except Exception as e:
        logger.warning(f"Failed to parse timestamp: {e}")
        return None
```

**Why good is better:** The worse version swallows the error and forces every caller to handle `None`. If timestamps must be valid, fail loud at the source. If they might legitimately be absent, distinguish "missing input" from "parse failure" with explicit types — don't conflate them with a logger.warning.
