---
name: rnd-data-science
description: "Use when performing numerical analysis, financial calculations, data wiring, chart generation, or any analytical task requiring Julia computation — CSV/XLS handling, statistical verification, and insight extraction"
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
1. LOAD JULIA TOOLS VIA ToolSearch BEFORE ANY COMPUTATION
2. VERIFY EVERY NUMERICAL RESULT WITH AN INDEPENDENT CHECK
3. VALIDATE INPUT DATA BEFORE PROCESSING — GARBAGE IN, GARBAGE OUT
4. NEVER HARDCODE INTERMEDIATE VALUES — RECOMPUTE FROM SOURCE
5. DOCUMENT UNITS, CURRENCY, AND TIME ZONES EXPLICITLY
```

## Setup: Julia MCP Tools

Julia is the primary computation environment. Load the tools at session start:

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

- [ ] Julia session used throughout (not ad-hoc shell arithmetic)
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
