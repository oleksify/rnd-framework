---
id: B4
role: builder
language: python
tags: [naming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Name functions by what they return and the condition that determines it, not by role or ceremony.
specializes: [P-SMALL-MODULES-01]
---

**Good:**
```python
def first_paying_customer_after(date: date) -> Customer | None: ...
```

**Worse:**
```python
class CustomerManager:
    def get_customer_helper(self, date: date) -> Customer | None: ...
```

**Why good is better:** The good name describes what is returned and the condition that determines it. The worse name uses `Manager` / `Helper` / `Service` suffixes that add ceremony without information. If you can describe a function by what it returns, the function shouldn't be a method on a class named for nothing.
