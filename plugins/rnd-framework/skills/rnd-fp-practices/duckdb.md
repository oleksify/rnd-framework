# DuckDB — FP Patterns

DuckDB-specific patterns for the five FP rules in SKILL.md.

## 1. CTEs as Analytical Pipeline Stages

Decompose multi-step analysis into named CTEs rather than nested subqueries.

**Do:**
```sql
WITH
  raw AS (SELECT * FROM read_parquet('events/*.parquet')),
  filtered AS (
    SELECT user_id, event_type, ts
    FROM raw WHERE event_type IN ('purchase', 'refund')
  ),
  enriched AS (
    SELECT f.*, u.country FROM filtered f JOIN users u USING (user_id)
  )
SELECT country, count(*) AS total FROM enriched
GROUP BY country ORDER BY total DESC;
```

**Don't:** write a single deeply-nested `SELECT` — each logical step should be a named CTE that can be read and replaced independently.

## 2. Window Functions as Pure Transformations

Window functions add computed columns without mutating rows — treat them as row-level pure functions.

**Do:**
```sql
WITH sales AS (SELECT * FROM read_csv('sales.csv')),
ranked AS (
  SELECT *,
    row_number() OVER (PARTITION BY region ORDER BY revenue DESC) AS rank,
    sum(revenue)  OVER (PARTITION BY region) AS region_total
  FROM sales
)
SELECT * FROM ranked WHERE rank <= 10;
```

**Don't:** use correlated subqueries to compute running totals or ranks — window functions express the same intent with no side effects and are vectorized by DuckDB.

## 3. QUALIFY for Declarative Row Filtering

Use `QUALIFY` to filter on window results in a single pass — no wrapping subquery needed.

**Do:**
```sql
SELECT user_id, session_id, started_at,
  row_number() OVER (PARTITION BY user_id ORDER BY started_at DESC) AS rn
FROM sessions
QUALIFY rn = 1;
```

**Don't:** wrap in a subquery just to reference the window alias: `SELECT * FROM (...) t WHERE t.rn = 1`.

## 4. list_transform / list_filter / list_reduce

DuckDB list functions are map/filter/reduce for nested arrays — use them instead of unnest-aggregate roundtrips.

**Do:**
```sql
SELECT order_id,
  list_transform(items, x -> x.price * x.qty) AS line_totals,
  list_reduce(list_transform(items, x -> x.price * x.qty), (a, b) -> a + b) AS total,
  list_filter(items, x -> x.category = 'electronics') AS electronics
FROM orders;
```

**Don't:** unnest, aggregate with GROUP BY, then rejoin — list functions handle this in a single pass.

## 5. read_parquet / read_csv as Pure Sources

Treat file-reading functions as pure sources. Query them directly; never stage into temp tables.

**Do:**
```sql
WITH src AS (
  SELECT * FROM read_parquet('s3://bucket/data/**/*.parquet', hive_partitioning = true)
)
SELECT year, month, sum(amount) FROM src GROUP BY year, month;
```

**Don't:** `CREATE TABLE tmp AS SELECT ...` then query `tmp` — temp tables add mutable state and require cleanup.

## 6. Struct Operations as Record Transformations

Bundle related columns into typed structs and transform them as values.

**Do:**
```sql
SELECT id,
  struct_pack(lat := lat, lon := lon) AS location,
  struct_pack(open := open_price, close := close_price,
              delta := close_price - open_price) AS ohlc
FROM market_data;
```

**Don't:** carry many loose columns through every CTE stage — structs make the pipeline's shape explicit and prevent column-name collisions.

## 7. Command-Query Separation

Queries return data; writes mutate state. Keep them separate.

**Do:**
```sql
-- query: returns relation, no side effects
SELECT product_id, sum(quantity) AS sold FROM read_parquet('orders.parquet') GROUP BY 1;

-- command: isolated write
COPY (SELECT product_id, sum(quantity) AS sold FROM read_parquet('orders.parquet') GROUP BY 1)
TO 'summary.parquet' (FORMAT PARQUET);
```

**Don't:** mix `INSERT INTO` inside a CTE that also returns rows — a CTE that both mutates and queries violates CQS and makes the pipeline non-reproducible.
