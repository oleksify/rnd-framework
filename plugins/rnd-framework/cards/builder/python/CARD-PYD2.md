---
id: PYD2
role: builder
language: python
tags: [configuration, validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Configure Pydantic v2 models with model_config = ConfigDict(...); never use the v1 inner class Config or mix both styles in one model.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle for Pydantic v2 model configuration: using the v1 `Config` class in a v2 model produces silently ignored settings, making the model's actual behavior unrepresentable from reading its source.

**Good:**
```python
from pydantic import BaseModel, ConfigDict

class UserOut(BaseModel):
    model_config = ConfigDict(
        from_attributes=True,    # replaces v1: orm_mode = True
        populate_by_name=True,   # replaces v1: allow_population_by_field_name
        str_strip_whitespace=True,
    )

    id: int
    name: str
    email: str
```

**Worse:**
```python
from pydantic import BaseModel

class UserOut(BaseModel):
    class Config:                # v1 style — silently ignored by Pydantic v2
        orm_mode = True          # has no effect; use from_attributes=True
        allow_population_by_field_name = True  # also ignored

    id: int
    name: str
    email: str
```

**Why good is better:** Pydantic v2 dropped the inner `Config` class — it is accepted without an error for backward compatibility but its fields are not applied, so `orm_mode = True` does nothing while `from_attributes=True` in `model_config` is what actually enables ORM instance parsing. Mixed configs (both `class Config` and `model_config`) are not merged; `model_config` wins silently, making the `Config` block dead code that misleads future readers. Use `ConfigDict` exclusively to ensure every setting you write is the setting that runs.
