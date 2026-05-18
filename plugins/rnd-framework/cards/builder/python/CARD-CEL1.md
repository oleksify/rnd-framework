---
id: CEL1
role: builder
language: python
tags: [boundaries, defensive-programming, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Pass only JSON-serializable primitives to Celery task signatures; never pass ORM instances or any object that is not safely picklable across process boundaries.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle for Celery: the broker serializes task arguments through JSON (or pickle); an ORM instance cannot cross that boundary safely — pass the primary key instead and re-fetch inside the worker.

**Good:**
```python
from celery import shared_task
from myapp.models import User

@shared_task
def send_welcome_email(user_id: int) -> None:
    user = User.objects.get(pk=user_id)
    _dispatch_email(user.email, user.name)

# caller
send_welcome_email.delay(user.id)
```

**Worse:**
```python
@shared_task
def send_welcome_email(user: User) -> None:
    _dispatch_email(user.email, user.name)

# caller
send_welcome_email.delay(user)   # passes ORM instance
```

**Why good is better:** Celery serializes task arguments at enqueue time and deserializes them in the worker process. An ORM instance carries a live database session that cannot survive serialization; with JSON serialization it raises immediately, and even with pickle it produces a stale, detached object that triggers lazy-load errors in the worker. Passing the primary key and re-fetching inside the task guarantees the worker sees the current database state and keeps the argument boundary explicit and testable.
