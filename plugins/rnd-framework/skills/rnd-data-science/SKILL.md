---
name: rnd-data-science
description: "Use when performing numerical analysis, financial calculations, data wiring, chart generation, or any analytical task requiring computation — Julia for statistics/charts/finance, DuckDB for SQL-expressible queries, CSV/Parquet aggregations, joins, and data exploration"
user-invocable: false
---

# R&D Data Science

## Overview

Analytical work fails silently. A wrong number in a table looks identical to a correct one. A chart with the wrong axis scale misleads without warning.

**Core principle:** Every numerical result must be independently verifiable. Show your computation, not just your conclusion.

## When to Use

- Financial calculations (P&L, cash flow, ratios, projections)
- CSV or XLS data ingestion, transformation, or export
- Chart and visualization generation
- Statistical analysis, aggregations, or derived metrics
- Data wiring between sources (APIs, files, databases)
- Insight extraction from structured or tabular data
- Any task where the output is numbers, tables, or charts

## The Iron Laws

```
1. LOAD COMPUTATION TOOLS (JULIA OR DUCKDB) BEFORE ANY COMPUTATION
2. VERIFY EVERY NUMERICAL RESULT WITH AN INDEPENDENT CHECK
3. VALIDATE INPUT DATA BEFORE PROCESSING — GARBAGE IN, GARBAGE OUT
4. NEVER HARDCODE INTERMEDIATE VALUES — RECOMPUTE FROM SOURCE
5. DOCUMENT UNITS, CURRENCY, AND TIME ZONES EXPLICITLY
```

## Tool Selection

Choose the right tool before starting. Use the decision table below:

| Task type | Preferred tool | Reason |
|---|---|---|
| SQL-expressible queries, aggregations, GROUP BY | DuckDB | Native SQL, fast, zero boilerplate |
| Joins across multiple CSV/Parquet files | DuckDB | Join syntax is concise; Julia merge is verbose |
| Data filtering, WHERE clauses, data exploration | DuckDB | Interactive CLI; no session state needed |
| Parquet file ingestion and transformation | DuckDB | Native Parquet support with no setup |
| Financial formulas (NPV, CAGR, DCF) | Julia | Mathematical expressiveness, precise control |
| Chart and visualization generation | Julia | Plots.jl; DuckDB has no chart output |
| Complex statistics, rolling windows, ML | Julia | StatsBase, RollingFunctions, MLJ |
| Mixed workload: query then compute/chart | DuckDB → Julia | Export from DuckDB as CSV, load into Julia |

When in doubt: if the task can be expressed in SQL, use DuckDB. If it needs a formula or chart, use Julia.

## Setup: DuckDB CLI

DuckDB is invoked via Bash. No install step needed if `duckdb` is on PATH.

```bash
# Inline query
duckdb -c "SELECT 1+1 AS result"

# Query a CSV directly
duckdb -c "SELECT * FROM read_csv('data.csv') LIMIT 5"

# Query a Parquet file
duckdb -c "SELECT * FROM 'data.parquet' LIMIT 5"

# Use a persistent database file
duckdb mydata.duckdb -c "SELECT count(*) FROM sales"

# Multi-line query (use single quotes around the SQL block)
duckdb -c "
  SELECT year, SUM(revenue) AS total
  FROM read_csv('sales.csv')
  GROUP BY year
  ORDER BY year
"
```

### DuckDB CSV and Parquet Queries

```bash
# Aggregate with grouping
duckdb -c "
  SELECT region, SUM(amount) AS total, AVG(amount) AS avg
  FROM read_csv('transactions.csv')
  GROUP BY region
  ORDER BY total DESC
"

# Filter and join two CSV files
duckdb -c "
  SELECT a.id, a.name, b.revenue
  FROM read_csv('customers.csv') a
  JOIN read_csv('revenue.csv') b ON a.id = b.customer_id
  WHERE b.revenue > 10000
"

# Export result to CSV
duckdb -c "
  COPY (
    SELECT category, SUM(sales) AS total
    FROM read_csv('data.csv')
    GROUP BY category
  ) TO 'output.csv' (HEADER, DELIMITER ',')
"

# Export to Parquet
duckdb -c "
  COPY (SELECT * FROM read_csv('data.csv'))
  TO 'output.parquet' (FORMAT PARQUET)
"
```

### DuckDB Verification Patterns

Always cross-check aggregations:

```bash
# Verify row count before and after filter
duckdb -c "SELECT count(*) AS total FROM read_csv('data.csv')"
duckdb -c "SELECT count(*) AS filtered FROM read_csv('data.csv') WHERE amount > 0"

# Verify sum reconciles with known total
duckdb -c "
  SELECT
    SUM(amount) AS computed_total,
    count(*) AS row_count,
    MIN(amount) AS min_val,
    MAX(amount) AS max_val
  FROM read_csv('transactions.csv')
"

# Cross-check a join: result row count must match left table
duckdb -c "SELECT count(*) FROM read_csv('customers.csv')"
duckdb -c "
  SELECT count(*) FROM read_csv('customers.csv') a
  JOIN read_csv('orders.csv') b ON a.id = b.customer_id
"
# If second count > first count: unexpected duplicates — investigate
```

## Setup: Julia MCP Tools

Julia is the primary computation environment for statistics, finance, and charts. Load the tools at session start:

```
ToolSearch: "select:mcp__julia__julia_eval"
ToolSearch: "select:mcp__julia__julia_list_sessions"
ToolSearch: "select:mcp__julia__julia_restart"
```

After loading, start a named session for the task:

```julia
# mcp__julia__julia_eval — session: "data-T<id>"
using Statistics, DataFrames, CSV
```

Use the same session name throughout the task so state accumulates correctly. If the session becomes stale or outputs are unexpected, call `mcp__julia__julia_restart` and re-run setup.

## Phase 0: Lean Specifications

Write Lean 4 theorems for numerical invariants BEFORE writing any computation code. Read the pre-registration criteria, identify invariants, and formalize them first — spec before code.

**When Lean is unavailable:** Run `which lean` or `lean --version`. If Lean is not installed, skip this phase and note it in the build manifest. Do not block on it.

### Common invariants to formalize

- **Bounds** — all values fall within `[lo, hi]`
- **NaN propagation** — no NaN in output when none are in input
- **Totality** — aggregation produces a result for every valid input
- **Associativity** — grouping order does not affect the result

### Lean 4 examples

```lean
-- Bounds checking: all values in [lo, hi]
theorem all_bounded (xs : List Float) (lo hi : Float)
    (h : ∀ x ∈ xs, lo ≤ x ∧ x ≤ hi) :
    ∀ x ∈ xs, lo ≤ x := by intro x hx; exact (h x hx).1

-- NaN propagation: no NaN in output if none in input
theorem no_nan_propagation (xs : List Float)
    (h : ∀ x ∈ xs, ¬ x.isNaN) (f : Float → Float)
    (hf : ∀ x, ¬ x.isNaN → ¬ (f x).isNaN) :
    ∀ y ∈ xs.map f, ¬ y.isNaN := by simp [List.mem_map]; aesop

-- Totality: aggregation is defined for every input (no partial functions)
theorem total_aggregation (xs : List Nat) :
    ∃ n : Nat, xs.foldl (· + ·) 0 = n := ⟨_, rfl⟩

-- Associativity: grouping doesn't affect result
theorem sum_associative (a b c : Nat) :
    a + (b + c) = (a + b) + c := by omega
```

## Phase 1: Data Validation

Before any computation, validate inputs:

```julia
# Schema validation
@assert ncol(df) == expected_cols "Expected $expected_cols columns, got $(ncol(df))"
@assert all(x -> x isa Number, df.amount) "amount column must be numeric"

# Range checks
@assert all(df.date .>= Date("2000-01-01")) "Unexpected historical dates"
@assert !any(isnan, df.value) "NaN values found in value column"
@assert !any(isinf, df.value) "Inf values found in value column"

# Completeness
missing_count = sum(ismissing, df.revenue)
@assert missing_count == 0 "$(missing_count) missing values in revenue"
```

**Flag and stop** if validation fails — do not proceed with bad data. Document what failed, what the data actually contains, and what was expected.

## Phase 2: CSV and XLS Handling

### Reading CSV

```julia
using CSV, DataFrames

df = CSV.read("data.csv", DataFrame;
    types = Dict(:date => Date, :amount => Float64),
    dateformat = "yyyy-mm-dd",
    missingstring = ["", "NA", "N/A", "null"]
)
```

Always specify `types` and `dateformat` explicitly — never rely on inference for dates or currency columns.

### Reading XLS/XLSX

```julia
using XLSX

xf = XLSX.readxlsx("report.xlsx")
sheet = xf["Sheet1"]
df = DataFrame(XLSX.eachtablerow(sheet))
```

Inspect the sheet names first with `XLSX.sheetnames(xf)` if the target sheet is not known in advance.

### Writing Output

```julia
CSV.write("output.csv", result_df)
XLSX.writetable("output.xlsx", result_df)
```

Always verify the written file: re-read and spot-check row count and column values.

## Phase 3: Financial Calculations

State currency, date range, and rounding convention explicitly before computing:

```julia
# Context: USD, fiscal year 2024, round to 2 decimal places
revenue   = sum(df[df.year .== 2024, :revenue])
cogs      = sum(df[df.year .== 2024, :cogs])
gross_profit = round(revenue - cogs; digits=2)
gross_margin = round(gross_profit / revenue * 100; digits=2)
```

### Verification Pattern

Every financial figure must be verified by an independent route:

```julia
# Primary calculation
total_receivables = sum(df.invoice_amount) - sum(df.payments)

# Independent cross-check
cross_check = df.opening_balance[1] + sum(df.invoice_amount) - sum(df.payments)
@assert isapprox(total_receivables, cross_check; atol=0.01) "Reconciliation failed"
```

### Common Finance Operations

```julia
# Compound growth rate (CAGR)
cagr(start, finish, years) = (finish / start)^(1/years) - 1

# Net Present Value
npv(rate, cashflows) = sum(cf / (1+rate)^t for (t, cf) in enumerate(cashflows))

# Moving average
using RollingFunctions
ma_30 = rollmean(df.price, 30)
```

## Phase 4: Numerical Verification

Every computed result requires an independent verification before it leaves the computation block:

| Result type | Verification method |
|---|---|
| Sum / total | Cross-add from a different grouping or column |
| Ratio / percentage | Multiply back and check against numerator |
| Aggregation | Spot-check 3+ individual rows manually |
| Time series | Verify endpoints and at least one midpoint |
| Joined/merged data | Confirm row count matches expectation; check for unexpected duplicates |

```julia
# Example: verify a join did not inflate rows
@assert nrow(joined) == nrow(left_df) "Join produced $(nrow(joined)) rows, expected $(nrow(left_df))"
```

## Phase 5: Chart and Visualization Generation

```julia
using Plots

# Always label axes, units, and data source
plot(df.date, df.revenue;
    title  = "Monthly Revenue — FY2024",
    xlabel = "Date",
    ylabel = "Revenue (USD)",
    label  = "Actual",
    legend = :topleft
)
savefig("charts/revenue-fy2024.png")
```

### Visualization Checklist

- [ ] Title describes what is shown (not just the variable name)
- [ ] Both axes are labeled with units
- [ ] Legend is present when multiple series exist
- [ ] Scale starts at zero for bar/area charts (or note when it doesn't)
- [ ] Date axis uses readable formatting (`Dates.format`)
- [ ] Output file is saved to a predictable path and the path is recorded in the build manifest

## Phase 6: Insight Extraction

After computing results, extract and state insights explicitly:

```markdown
## Key Findings

1. Revenue grew 12.3% YoY (Q4 2023: $4.2M → Q4 2024: $4.7M)
2. Gross margin compressed 2.1pp due to COGS increase in March
3. Three customers account for 61% of receivables outstanding >90 days
```

Distinguish **findings** (what the data says) from **interpretations** (what it might mean). Flag interpretations as such.

## Artifact Checklist

Before marking the task complete:

- [ ] Lean specs written for numerical invariants (when Lean available)
- [ ] Computation tool selected appropriately (DuckDB for SQL queries, Julia for formulas/charts)
- [ ] Input data validated before processing
- [ ] Every financial figure has an independent cross-check assertion
- [ ] CSV/XLS output re-read and spot-checked after writing
- [ ] Charts saved to files, paths recorded
- [ ] Units, currency, and time zone documented for every numerical result
- [ ] Key insights stated explicitly in plain language
- [ ] Build manifest references all output files (data, charts, reports)

## Related Skills

- `rnd-framework:rnd-building` — TDD discipline and build manifest production
- `rnd-framework:rnd-verification` — Independent verification protocol
- `rnd-framework:rnd-debugging` — When computed values diverge from expectation
