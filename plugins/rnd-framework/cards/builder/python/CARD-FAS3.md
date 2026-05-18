---
id: FAS3
role: builder
language: python
tags: [boundaries, abstraction, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use FastAPI BackgroundTasks for fire-and-forget effects that can be lost on restart; use Celery when the task must survive process death or needs retries.
specializes: [P-SMALL-MODULES-01]
---

Specializes the small-modules principle by separating the choice of task execution mechanism from business logic: the handler stays thin while the delivery guarantee is expressed at the boundary.

**Good:**
```python
from fastapi import BackgroundTasks, FastAPI
from .email import send_welcome_email

app = FastAPI()

# BackgroundTasks: acceptable for low-stakes notifications
@app.post("/users/")
def create_user(payload: UserIn, background_tasks: BackgroundTasks) -> UserOut:
    user = create_user_in_db(payload)
    background_tasks.add_task(send_welcome_email, user.email)
    return UserOut.model_validate(user)

# Celery: use when the task must complete even if the server restarts
from .tasks import send_invoice_task  # Celery task

@app.post("/orders/")
def create_order(payload: OrderIn) -> OrderOut:
    order = create_order_in_db(payload)
    send_invoice_task.delay(order.id)   # persisted to broker
    return OrderOut.model_validate(order)
```

**Worse:**
```python
@app.post("/orders/")
async def create_order(payload: OrderIn) -> OrderOut:
    order = create_order_in_db(payload)
    await send_invoice(order.id)   # blocks the response AND fails silently on crash
    return OrderOut.model_validate(order)
```

**Why good is better:** `BackgroundTasks` runs after the response is sent but inside the same process — if the worker restarts mid-task, the work is lost with no record. Celery persists the task message to a broker (Redis, RabbitMQ) before acknowledging the request, so a worker crash triggers automatic retry. Choose by delivery guarantee: `BackgroundTasks` for idempotent best-effort tasks (welcome emails), Celery for business-critical work (invoices, payment confirmations) where losing a task is unacceptable.
