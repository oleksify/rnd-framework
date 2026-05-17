---
id: B5
role: builder
language: python
tags: [control-flow, early-return]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
---

### Card B5: Early return over sentinel tracking

**Good:**
```python
def find_admin(users: list[User]) -> User | None:
    for user in users:
        if user.is_admin:
            return user
    return None
```

**Worse:**
```python
def find_admin(users: list[User]) -> User | None:
    result = None
    for user in users:
        if user.is_admin and result is None:
            result = user
    return result
```

**Why good is better:** Early return makes the control flow obvious and the algorithm short-circuit. Sentinel tracking is a hangover from languages without `return` mid-function. Don't avoid multiple returns; use them when they make intent immediate.
