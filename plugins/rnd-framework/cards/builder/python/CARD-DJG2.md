---
id: DJG2
role: builder
language: python
tags: [control-flow, boundaries, error-handling]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use select_related for ForeignKey/OneToOne traversals and prefetch_related for reverse-FK or ManyToMany; mixing them up causes either extra queries or a Cartesian-product JOIN.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for Django ORM N+1: the choice between `select_related` and `prefetch_related` is not aesthetic — each targets a different join topology, and the wrong pick either leaves N+1 in place or produces a bloated result set.

**Good:**
```python
from .models import Order

def get_orders_with_customer_and_items(shop_id: int) -> list[Order]:
    return list(
        Order.objects
        .filter(shop_id=shop_id)
        .select_related("customer")          # ForeignKey: single JOIN
        .prefetch_related("items")           # reverse-FK: separate IN query
    )
```

**Worse:**
```python
def get_orders_with_customer_and_items(shop_id: int) -> list[Order]:
    orders = Order.objects.filter(shop_id=shop_id)
    for order in orders:
        _ = order.customer   # SELECT per order (N+1)
        _ = order.items.all()  # SELECT per order (N+1)
    return list(orders)
```

**Why good is better:** `select_related` follows ForeignKey and OneToOne links in a single SQL JOIN — use it when each row has exactly one related object. `prefetch_related` handles reverse-FK and ManyToMany by issuing a separate `SELECT … WHERE id IN (…)` and stitching results in Python — use it for collections. Applying `select_related` to a ManyToMany multiplies rows; applying `prefetch_related` to a ForeignKey works but is slower than a JOIN. Match the tool to the relationship type.
