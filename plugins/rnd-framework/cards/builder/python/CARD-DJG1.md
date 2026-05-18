---
id: DJG1
role: builder
language: python
tags: [boundaries, control-flow, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Force Django QuerySet evaluation at the service boundary; never pass unevaluated QuerySets to callers where re-evaluation is invisible.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for Django ORM: a QuerySet is a lazy description of a query, not a result — passing it across a function boundary means the database hit occurs wherever the caller first iterates or accesses it, making I/O timing invisible.

**Good:**
```python
from django.db.models import QuerySet
from .models import Article

def get_published_articles() -> list[Article]:
    return list(Article.objects.filter(status="published").order_by("-created_at"))
```

**Worse:**
```python
def get_published_articles() -> QuerySet:
    return Article.objects.filter(status="published").order_by("-created_at")
    # caller iterates it in a template → implicit DB hit at render time
```

**Why good is better:** An unevaluated QuerySet defers its SELECT to the first iteration. When passed to a template, it executes during rendering — outside any transaction context, timing measurement, or error-handling boundary you control. Calling `list()` (or `.values_list()`, `.count()`, etc.) at the service layer converts the QuerySet to a plain Python value, collapses the I/O into one predictable place, and makes the function's signature honest about what it returns.
