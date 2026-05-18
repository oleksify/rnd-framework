---
id: P-PY1
role: planner
language: python
tags: [decomposition, scope, boundaries]
applicable_task_types: [new-feature, refactor]
scope: Decompose Python tasks at stdlib vs third-party boundaries and prefer pure functions over classes.
specializes: [P-SMALL-MODULES-01]
---

**Good spec:**
> Add CSV export for invoice line items.
>
> Constraints:
> - One function: `export_csv(line_items: list[LineItem]) -> str` in `invoices/export.py`
> - Uses only stdlib `csv` module — no pandas, no third-party serializers
> - Returns the CSV as a string; caller decides where to write it
> - Out of scope: streaming, encoding options, multi-sheet, compression
> - Hard cap: 25 lines including imports

**Worse spec:**
> Implement a flexible CSV export module for invoices. Support multiple formats and allow configuration of delimiters, encodings, and output destinations. Design for future extensibility with other data types.

**Why good is better:** The good spec draws the stdlib/third-party boundary explicitly and constrains output to a pure function returning a string — callers are testable without touching the filesystem. The worse spec invites pandas, openpyxl, and an `Exporter` base-class hierarchy before a single line of business logic is written. In Python, the boundary between "stdlib is enough" and "pull in a library" is a deliberate architectural decision; make it in the spec, not the implementation.
