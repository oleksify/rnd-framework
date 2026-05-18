---
id: SQA1
role: builder
language: python
tags: [abstraction, control-flow, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use the SQLAlchemy 2 execute/select API exclusively; never mix it with the legacy query() style in the same codebase.
specializes: [P-SMALL-MODULES-01]
---

Specializes the small-modules principle for SQLAlchemy 2: each query pattern has one authoritative shape — mixing the 1.x `query()` style with the 2.x `execute(select())` style forces readers to hold two mental models simultaneously.

**Good:**
```python
from sqlalchemy import select
from sqlalchemy.orm import Session

def get_active_users(session: Session) -> list[User]:
    stmt = select(User).where(User.is_active)
    return session.scalars(stmt).all()
```

**Worse:**
```python
def get_active_users(session: Session) -> list[User]:
    return session.query(User).filter(User.is_active).all()
```

**Why good is better:** SQLAlchemy 2.0 deprecated `Session.query()` in favour of `session.execute(select(...))` / `session.scalars(...)`. The legacy style still runs but is excluded from type stubs and future features. More critically, mixing both styles in one codebase means any query can be written two ways — code review, search, and tooling all become harder. Pick the modern form once and apply it everywhere.
