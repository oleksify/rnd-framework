---
id: HTX1
role: builder
language: python
tags: [boundaries, abstraction, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Create an httpx.AsyncClient once per application lifetime or request batch; never instantiate AsyncClient inside a per-request handler.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for httpx: client construction is an I/O-effect that allocates a connection pool — doing it per request destroys pooling and incurs TLS handshake cost on every call.

**Good:**
```python
import httpx
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI

@asynccontextmanager
async def lifespan(app: FastAPI):
    async with httpx.AsyncClient() as client:
        app.state.http = client
        yield

app = FastAPI(lifespan=lifespan)

def get_http(request) -> httpx.AsyncClient:
    return request.app.state.http

@app.get("/posts/{post_id}")
async def fetch_post(post_id: int, http: httpx.AsyncClient = Depends(get_http)) -> dict:
    response = await http.get(f"https://api.example.com/posts/{post_id}")
    response.raise_for_status()
    return response.json()
```

**Worse:**
```python
import httpx

async def fetch_data(url: str) -> dict:
    async with httpx.AsyncClient() as client:   # new pool per call
        response = await client.get(url)
        response.raise_for_status()
        return response.json()
```

**Why good is better:** Each `httpx.AsyncClient()` construction creates a new connection pool; tearing it down after every request closes all connections and discards keep-alive state, so the next call opens a fresh TCP connection and repeats the TLS handshake. A long-lived client reuses connections across requests, which reduces latency and resource churn. The `lifespan` + `Depends` pattern attaches the client to the app, drives cleanup on shutdown, and keeps the handler testable via `app.dependency_overrides[get_http]`.
