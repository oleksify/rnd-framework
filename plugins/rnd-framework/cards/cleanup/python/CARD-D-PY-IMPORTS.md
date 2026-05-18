---
id: D-PY-IMPORTS
role: cleanup
language: python
tags: [dead-code, imports]
applicable_task_types: [refactor]
scope: Distinguish genuinely unused imports from intentional re-exports before deleting them.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```python
# utils/__init__.py
from .formatters import format_date
from .validators import validate_email
from .parsers import parse_csv   # ruff flags as unused
```
```python
# elsewhere in the codebase
from mypackage.utils import parse_csv  # direct consumer
```

**After:**
```python
# utils/__init__.py
from .formatters import format_date
from .validators import validate_email
from .parsers import parse_csv  # public API re-export — keep
```

**Why after is better:** A name appearing in `__init__.py` with no same-file usage is the correct form for a public-API re-export — removing it breaks callers importing from the package surface. Before deleting any import flagged by ruff or unused-import tooling, verify whether the name is consumed by outside modules (`grep -r 'from mypackage.utils import parse_csv'`). Delete only if no consumer exists; otherwise add `# noqa: F401` with a brief comment naming the public-surface intent.
