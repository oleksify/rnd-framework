---
id: FAS2
role: builder
language: python
tags: [boundaries, validation, abstraction]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Declare response_model on every endpoint so FastAPI validates and serializes output; never return raw dicts from typed endpoints.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle for FastAPI responses: `response_model` makes the output contract explicit at the type level, preventing fields from leaking or going missing silently.

**Good:**
```python
from pydantic import BaseModel, ConfigDict
from fastapi import FastAPI

class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: str

app = FastAPI()

@app.get("/users/{user_id}", response_model=UserOut)
def read_user(user_id: int) -> User:
    return db.get(User, user_id)   # response_model + from_attributes does the rest
```

**Worse:**
```python
@app.get("/users/{user_id}")
def read_user(user_id: int) -> dict:
    user = db.get(User, user_id)
    return {"id": user.id, "name": user.name, "hashed_password": user.hashed_password}
```

**Why good is better:** Without `response_model`, FastAPI performs no output validation — extra fields like `hashed_password` reach the client, missing fields are silently absent, and the OpenAPI schema is generated from the raw `dict` annotation, which gives clients no type information. `response_model=UserOut` runs Pydantic serialization on every response: unknown fields are stripped, missing required fields raise a 500 before the response leaves the server, and the OpenAPI docs show the exact shape callers can rely on.
