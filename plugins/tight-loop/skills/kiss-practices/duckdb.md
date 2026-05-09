# DuckDB — KISS Rules

## Queries

- Use `read_csv()`, `read_parquet()`, `read_json()` directly in queries — don't create tables from files unless you need to query them repeatedly
- Use simple SQL over CTEs when a single `SELECT` with joins and subqueries is clear enough
- Don't create views for one-off analysis queries — views are for queries reused from multiple places
- Use `COPY ... TO` for exporting results — don't pipe through application code when DuckDB can write directly
- Use `duckdb -c 'SQL'` for one-shot queries — don't create persistent databases for throwaway analysis

## Types & Schema

- Let DuckDB infer types from files — don't specify column types manually unless inference gets it wrong
- Use `DESCRIBE` or `SUMMARIZE` to understand data before writing queries — don't guess at column names or types
- Don't create custom types or macros for single-use transformations

## Analysis Patterns

- Use window functions (`OVER`, `PARTITION BY`) for ranking and running calculations — don't self-join
- Use `GROUP BY ALL` when grouping by all non-aggregated columns — don't list every column
- Use `EXCLUDE` in `SELECT * EXCLUDE (col)` to drop columns — don't list every column you want to keep
- Use `UNPIVOT` and `PIVOT` instead of manual `CASE WHEN` for reshaping data
- Use `QUALIFY` to filter window function results — don't wrap in a subquery
