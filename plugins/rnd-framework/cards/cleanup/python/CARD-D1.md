---
id: D1
role: cleanup
language: python
tags: [dead-code, defensive-programming]
applicable_task_types: [refactor]
scope: small
---

### Card D1: Dead defensive code

**Before (180 chars):**
```python
def total_price(items: list[Item]) -> Decimal:
    if items is None:
        return Decimal(0)
    if len(items) == 0:
        return Decimal(0)
    total = Decimal(0)
    for item in items:
        if item is None:
            continue
        if item.price is None:
            continue
        total += item.price
    return total
```

**After (90 chars):**
```python
def total_price(items: list[Item]) -> Decimal:
    return sum((item.price for item in items), Decimal(0))
```

**Why after is better:** The "before" guards against conditions that the type signature already excludes (`list[Item]` cannot be `None`; `Item.price` should not be optional). Each guard either hides a bug at the wrong layer or handles a case that cannot occur. The "after" trusts its types and lets violations fail loud where they actually happen.
