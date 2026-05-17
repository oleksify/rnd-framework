---
id: D2
role: cleanup
language: python
tags: [dead-code, comments]
applicable_task_types: [refactor]
scope: small
specializes: [P-SMALL-MODULES-01]
---

### Card D2: Comments that restate the code

**Before:**
```python
# Increment the counter
counter += 1

# Check if user is admin
if user.is_admin:
    # Grant access
    grant_access(user)
```

**After:**
```python
counter += 1

if user.is_admin:
    grant_access(user)
```

**Why after is better:** Comments should explain *why*, not *what*. `# Increment the counter` adds noise without information. Good code documents what it does through naming; comments are reserved for the things the code can't say — intent, history, constraints, surprises.
