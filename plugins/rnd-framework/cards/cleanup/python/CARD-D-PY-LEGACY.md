---
id: D-PY-LEGACY
role: cleanup
language: python
tags: [dead-code, debugging]
applicable_task_types: [refactor]
scope: Remove debug artifacts and commented-out code blocks without ceremony or hesitation.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```python
def process_order(order_id: int) -> Order:
    print(f"DEBUG processing {order_id}")  # debug print
    order = db.get(order_id)
    # import pdb; pdb.set_trace()
    # result = old_process(order)   # keep for now just in case
    breakpoint()
    return order
```

**After:**
```python
def process_order(order_id: int) -> Order:
    return db.get(order_id)
```

**Why after is better:** Debug artifacts (`print`, `breakpoint`, `pdb.set_trace`) are not documentation — they are noise that signals incomplete cleanup and can leak sensitive data to production logs. Commented-out code is worse: it implies the code might return, but git already preserves history. Delete all three categories unconditionally. If the removed logic is genuinely needed, retrieve it from git; do not leave a graveyard.
