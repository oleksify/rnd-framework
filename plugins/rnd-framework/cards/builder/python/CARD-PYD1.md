---
id: PYD1
role: builder
language: python
tags: [validation, boundaries, control-flow]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use field_validator for single-field constraints, model_validator for cross-field invariants, and computed_field for derived read-only values.
specializes: [P-IMPOSSIBLE-01]
---

**Good:**
```python
from pydantic import BaseModel, computed_field, field_validator, model_validator

class DateRange(BaseModel):
    start: date
    end: date
    label: str

    @field_validator("label")
    @classmethod
    def label_not_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("label must not be blank")
        return v.strip()

    @model_validator(mode="after")
    def end_after_start(self) -> "DateRange":
        if self.end <= self.start:
            raise ValueError("end must be after start")
        return self

    @computed_field
    @property
    def duration_days(self) -> int:
        return (self.end - self.start).days
```

**Worse:**
```python
class DateRange(BaseModel):
    start: date
    end: date
    label: str
    duration_days: int = 0   # mutable, stale if start/end change

    @model_validator(mode="after")
    def validate_all(self) -> "DateRange":
        if not self.label.strip():            # cross-field for a single-field rule
            raise ValueError("label blank")
        if self.end <= self.start:
            raise ValueError("end before start")
        self.duration_days = (self.end - self.start).days  # side-effect in validator
        return self
```

**Why good is better:** Packing every check into one `model_validator` hides which fields are involved and mutates model state as a side effect — validators are meant to validate, not to compute. `field_validator` runs before `model_validator`, is invoked only for its declared field, and can short-circuit early. `computed_field` keeps derived values read-only and always in sync with their sources: Pydantic recomputes them on serialization so they can never be manually set to a stale value.
