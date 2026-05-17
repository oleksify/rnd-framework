---
id: B3
role: builder
language: python
tags: [defensive-programming, validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
---

### Card B3: Defensive validation at the wrong boundary

**Good:**
```python
def hourly_rate(employee: Employee) -> Decimal:
    return employee.annual_salary / WORKING_HOURS_PER_YEAR
```

**Worse:**
```python
def hourly_rate(employee: Employee | None) -> Decimal:
    if employee is None:
        logger.warning("Got None employee in hourly_rate")
        return Decimal(0)
    if employee.annual_salary is None:
        return Decimal(0)
    if employee.annual_salary < 0:
        logger.warning(f"Negative salary for {employee.id}")
        return Decimal(0)
    return employee.annual_salary / WORKING_HOURS_PER_YEAR
```

**Why good is better:** The worse version handles cases at the wrong layer. If employees can lack salaries, encode that in the type at the source. If they cannot, let the call fail loud at the boundary that produced an invalid employee. Silently returning `0` propagates the bug into payroll — louder is safer than helpful.
