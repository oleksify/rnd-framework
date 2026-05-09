# PostgreSQL — KISS Rules

## Queries

- Use simple SQL before reaching for CTEs — a subquery or join is often clearer
- Don't create database views for one-off queries — views are for queries used from multiple places
- Don't create stored procedures when application code works — procedures are for database-level reuse, not application logic
- Use `WHERE` clauses over `HAVING` when filtering non-aggregated columns
- Don't use `SELECT *` in application queries — list the columns you need

## Schema

- Don't normalize beyond what the queries need — a denormalized column that avoids a join is often the right call
- Don't add indexes speculatively — add them when `EXPLAIN ANALYZE` shows a sequential scan on a query that matters
- Use `text` over `varchar(n)` unless a length constraint is a business rule — PostgreSQL stores them identically
- Don't create custom types (domains, enums) for values only used in one table
- Use simple foreign keys — don't create junction tables for 1:1 relationships

## Migrations

- Keep migrations simple: `CREATE TABLE`, `ALTER TABLE`, `CREATE INDEX`
- Don't create migration helper functions or DSLs — the SQL is the documentation
- Don't add rollback logic for destructive migrations in production — you'll restore from backup, not roll back
- One concern per migration — don't combine schema changes with data migrations
