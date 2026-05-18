---
id: FAS1
role: builder
language: python
tags: [boundaries, abstraction, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Inject dependencies via FastAPI's Depends() system; never create database sessions ad-hoc inside request handlers.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for FastAPI: session creation is an I/O effect that belongs in a scoped dependency, not woven through handler logic.

**Good:**
```python
from collections.abc import Generator
from fastapi import Depends, FastAPI
from sqlalchemy.orm import Session
from .database import SessionLocal

def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

app = FastAPI()

@app.get("/users/{user_id}")
def read_user(user_id: int, db: Session = Depends(get_db)) -> dict:
    user = db.get(User, user_id)
    return {"id": user.id, "name": user.name}
```

**Worse:**
```python
@app.get("/users/{user_id}")
def read_user(user_id: int) -> dict:
    db = SessionLocal()          # session created ad-hoc — never closed on exception
    user = db.query(User).filter(User.id == user_id).first()
    db.close()
    return {"id": user.id, "name": user.name}
```

**Why good is better:** The ad-hoc version leaks the session whenever the handler raises before `db.close()` — connection pool exhaustion happens silently under load. `Depends(get_db)` wraps the yield in a try/finally that FastAPI drives through the full request lifecycle including exception paths. A dependency is also mockable in tests via `app.dependency_overrides`, so the handler can be tested without a real database.
