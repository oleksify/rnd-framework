# PostgreSQL — FP Patterns

## 1. CTEs as Named Pipeline Stages

Express multi-step transformations as a chain of named CTEs instead of nested subqueries.

**Do:**
```sql
WITH
  active_orders AS (
    SELECT id, customer_id, total FROM orders WHERE status = 'active'
  ),
  with_discounts AS (
    SELECT ao.id, ao.customer_id,
           ao.total * (1 - COALESCE(d.pct, 0)) AS discounted_total
    FROM active_orders ao LEFT JOIN discounts d USING (customer_id)
  ),
  aggregated AS (
    SELECT customer_id, SUM(discounted_total) AS revenue
    FROM with_discounts GROUP BY customer_id
  )
SELECT * FROM aggregated ORDER BY revenue DESC;
```

**Don't:** nest subqueries three levels deep — each level hides its stage name and makes independent testing impossible.

## 2. Set-Based Operations Over Row-by-Row Cursors

Operate on entire result sets; avoid `FETCH`/`LOOP` cursors.

**Do:**
```sql
UPDATE orders
SET    status = 'fulfilled'
FROM   shipments
WHERE  orders.id = shipments.order_id
  AND  shipments.delivered_at IS NOT NULL;
```

**Don't:**
```sql
FOR rec IN SELECT * FROM orders LOOP          -- one row at a time
  IF EXISTS (SELECT 1 FROM shipments WHERE order_id = rec.id ...) THEN
    UPDATE orders SET status = 'fulfilled' WHERE id = rec.id;
  END IF;
END LOOP;
```

## 3. IMMUTABLE / STABLE / VOLATILE Annotations

Declare the correct volatility so the planner can cache and inline results.

**Do:**
```sql
-- Pure math → IMMUTABLE: no DB access, same inputs always give same output
CREATE FUNCTION tax_rate(region TEXT) RETURNS NUMERIC
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  RETURN CASE region WHEN 'EU' THEN 0.20 ELSE 0.10 END;

-- Reads rows, stable within a statement → STABLE
CREATE FUNCTION user_email(uid UUID) RETURNS TEXT
  LANGUAGE sql STABLE
  RETURN (SELECT email FROM users WHERE id = uid);
```

**Don't:** leave functions as `VOLATILE` (the default) when they only read data — the planner re-executes them per row instead of caching.

## 4. Window Functions as Pure Transformations

Compute derived columns without subqueries or self-joins.

**Do:**
```sql
SELECT order_id, customer_id, amount,
  SUM(amount)  OVER w                      AS customer_total,
  RANK()       OVER (w ORDER BY amount DESC) AS rank_by_value,
  amount / NULLIF(SUM(amount) OVER w, 0)   AS share
FROM orders
WINDOW w AS (PARTITION BY customer_id);
```

**Don't:** use correlated subqueries for running totals or ranks — they execute once per row and cannot compose without re-scanning.

## 5. Pure SQL Functions

Write functions as SQL expressions, not procedural routines, when no control flow is needed.

**Do:**
```sql
CREATE FUNCTION full_name(first TEXT, last TEXT) RETURNS TEXT
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  RETURN trim(first || ' ' || last);

CREATE FUNCTION fiscal_quarter(d DATE) RETURNS INT
  LANGUAGE sql IMMUTABLE PARALLEL SAFE
  RETURN EXTRACT(QUARTER FROM d)::INT;
```

**Don't:** wrap simple expressions in `PL/pgSQL` `BEGIN … END` — the planner cannot inline procedural bodies, losing IMMUTABLE caching.

## 6. Command-Query Separation

Read-only queries use SQL functions; mutations use procedures or explicit DML.

**Do:**
```sql
-- Query: pure SELECT, no side-effects
CREATE FUNCTION orders_for_customer(cid UUID)
  RETURNS SETOF orders LANGUAGE sql STABLE
  RETURN SELECT * FROM orders WHERE customer_id = cid;

-- Command: procedure that mutates, returns nothing
CREATE PROCEDURE cancel_order(oid UUID) LANGUAGE sql
  BEGIN ATOMIC
    UPDATE orders SET status = 'cancelled', updated_at = now()
    WHERE id = oid;
  END;
```

**Don't:** return rows AND mutate in the same function — such functions cannot be called inside read-only transactions (`SET TRANSACTION READ ONLY`).
