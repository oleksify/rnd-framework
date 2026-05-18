---
id: R-PY-SQA1
role: reality-auditor
language: python
tags: [anomaly, cross-check, skepticism]
applicable_task_types: [new-feature, bugfix, refactor]
scope: SQLAlchemy model declarations and actual database columns must match or ORM queries silently diverge from the schema.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by requiring a runtime cross-check between the ORM model definition and the live database schema: column declarations in Python code cannot be trusted without verifying the actual table structure.

**Good audit observation:**
> The `User` model at `models/user.py` declares five columns: `id`, `email`, `created_at`, `role`, and `is_active`. Running `from sqlalchemy import inspect; inspect(engine).get_columns(User.__tablename__)` against the development database returns six columns — the actual table also has `deleted_at`, which is absent from the ORM model. Queries that filter on `deleted_at` will fail with `InvalidRequestError`; queries that omit the filter will return soft-deleted rows. Either add `deleted_at` to the model or document that this column is managed outside the ORM. The drift was likely introduced by a migration that was not reflected back into the model file.

**Worse audit observation:**
> The SQLAlchemy model defines the expected columns for the User table. The schema looks consistent with the application's requirements.

**Why good is better:** The good observation runs the concrete `inspect(engine).get_columns()` cross-check and finds a column the model does not declare. The worse observation accepts the model as authoritative without comparing it against the actual table. SQLAlchemy models and database schemas drift whenever migrations add or remove columns without a corresponding model update — the ORM will not raise an error on startup, so silent drift persists until a query touches the diverged column.
