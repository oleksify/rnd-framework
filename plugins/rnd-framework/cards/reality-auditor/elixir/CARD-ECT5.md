---
id: ECT5
role: reality-auditor
language: elixir
tags: [anomaly, skepticism, inconsistency]
applicable_task_types: [new-feature, bugfix, infra]
scope: Ecto migrations run sequentially; a migration that reads or transforms data set by a prior migration will fail on a fresh database where both run in order.
specializes: [P-EFFECTS-EDGE-01]
---

Specializes the effects-at-the-edge principle for Ecto migrations by flagging data dependencies between migrations — dependencies that work on an existing production database but break on a fresh setup where both run together.

**Good audit output:**
> Migration `20240301_add_status_to_orders.exs` adds a `status` column with `default: "pending"`. Migration `20240302_backfill_order_status.exs` runs `Repo.update_all(Order, set: [status: "completed"])` for orders where `inserted_at < ~D[2024-01-01]`. On a fresh database, both migrations run in sequence — the backfill will correctly see the `status` column from the prior migration. No data dependency anomaly in order. However, `Repo.update_all(Order, ...)` uses the Elixir `Order` schema — if `Order` is later changed (fields removed, validations tightened), this migration will fail on rerun. Flag: prefer raw SQL (`execute "UPDATE orders SET ..."`) in data migrations to decouple from schema evolution.

**Worse audit output:**
> The migration adds a default value and a subsequent migration backfills data. This is a standard two-migration pattern.

**Why good is better:** A migration that calls `Repo.update_all` with an application schema is coupled to the schema's current shape — if the schema later adds `@enforce_keys` or a required virtual field, the migration will crash on a fresh database setup. Raw SQL migrations are always safe to replay because they operate on the database level, not the Elixir module level. The good output names the specific risk and gives the concrete fix.
