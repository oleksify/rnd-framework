---
id: SQA3
role: builder
language: python
tags: [control-flow, error-handling, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Treat each unit of work as a short-lived session; Session.commit() ends the transaction and expires all loaded objects.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for SQLAlchemy session lifecycle: a `commit()` is a boundary event — attributes accessed on ORM objects after it trigger new SELECT statements, and long-lived sessions accumulate stale state that is hard to reason about.

**Good:**
```python
from sqlalchemy.orm import Session

def create_and_notify(session: Session, data: dict) -> int:
    user = User(**data)
    session.add(user)
    session.commit()
    user_id = user.id  # safe: id is refreshed after commit
    return user_id     # return the scalar; don't pass the ORM object out
```

**Worse:**
```python
def create_and_notify(session: Session, data: dict) -> User:
    user = User(**data)
    session.add(user)
    session.commit()
    # user is now expired; caller accesses user.email → triggers a SELECT
    # if the session is already closed, this raises DetachedInstanceError
    return user
```

**Why good is better:** After `session.commit()`, SQLAlchemy expires all attributes on loaded objects. Any attribute access on the returned `user` inside the caller re-issues a SELECT — which fails with `DetachedInstanceError` if the session is closed. Returning plain scalars (ids, dicts) across the commit boundary keeps the caller free of implicit I/O and eliminates the entire class of detachment errors.
