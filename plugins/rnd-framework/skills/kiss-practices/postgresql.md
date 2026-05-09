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

## Polish

- Name tables and columns consistently: either `snake_case` plural nouns for tables (`user_sessions`) or singular — pick one and don't mix within a schema
- Comment constraints and indexes that implement non-obvious business rules — `-- enforces one active subscription per account`; don't comment on what `NOT NULL` or `PRIMARY KEY` does
- Order columns in a `CREATE TABLE` predictably: primary key first, foreign keys next, required columns, nullable columns last — makes schemas scannable across tables
- Use consistent CTE naming within a query: either descriptive nouns (`monthly_totals`) or verb phrases (`compute_totals`) — don't mix both styles in one WITH clause
