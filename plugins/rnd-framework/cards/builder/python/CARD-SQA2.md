---
id: SQA2
role: builder
language: python
tags: [control-flow, boundaries, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Declare relationship loading strategy at the query site with selectinload or joinedload; never rely on lazy-load defaults that issue one query per row.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for SQLAlchemy: each lazy-loaded attribute access is an implicit I/O effect — collecting those effects at a single eager-load declaration at the query boundary prevents N+1 queries.

**Good:**
```python
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

def get_orders_with_items(session: Session) -> list[Order]:
    stmt = (
        select(Order)
        .where(Order.status == "open")
        .options(selectinload(Order.items))
    )
    return session.scalars(stmt).all()
```

**Worse:**
```python
def get_orders_with_items(session: Session) -> list[Order]:
    orders = session.scalars(select(Order).where(Order.status == "open")).all()
    for order in orders:
        _ = order.items  # triggers a SELECT per order
    return orders
```

**Why good is better:** With lazy loading (the SQLAlchemy default), accessing `order.items` inside a loop issues one `SELECT` per order row — N orders produce N+1 queries. `selectinload` issues a single follow-up `SELECT … WHERE order_id IN (…)` for all orders at once. Use `selectinload` for collections and `joinedload` for many-to-one relationships; declare the strategy at the query, not on the relationship definition, so callers can override it per context.
