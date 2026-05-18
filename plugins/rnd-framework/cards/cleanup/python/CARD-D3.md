---
id: D3
role: cleanup
language: python
tags: [dead-code, wrappers, abstraction]
applicable_task_types: [refactor]
scope: Delete wrapper classes that add no logic over stdlib operations; use idiomatic stdlib at call sites.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```python
class StringUtils:
    @staticmethod
    def is_empty(s: str | None) -> bool:
        return s is None or len(s) == 0

    @staticmethod
    def safe_strip(s: str | None) -> str:
        if s is None:
            return ""
        return s.strip()
```

**After:**
Delete the file. Use `not s` and `(s or "").strip()` at call sites.

**Why after is better:** `StringUtils` is a class with no state that exists to wrap two stdlib operations behind names that obscure what they do. The "after" form is shorter, idiomatic, and doesn't require importing a custom utility module. Wrappers are tax — only build them when they earn their cost with non-trivial logic.
