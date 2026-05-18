---
id: MYP1
role: verifier
language: python
tags: [critique-evidence, fail-case, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Unjustified Any annotations or type-ignore suppression escape mypy and must be replaced with concrete types.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by treating `Any` and `# type: ignore` as type-system holes: they suppress errors rather than expressing intent, making impossible states silently possible again.

**Good review comment:**
> FAIL. `parse` at `src/parser.py:12` is typed `def parse(x: Any) -> Any`. The function is only ever called with `str` and always returns a `dict[str, int]` — use those types. Untyped `Any` means mypy cannot flag callers that pass the wrong type or mishandle the return value. Replace with `def parse(x: str) -> dict[str, int]` and run `mypy src/parser.py` to confirm no additional errors surface.

**Worse review comment:**
> The `Any` annotations in `parse` could be made more specific if the types are known. Consider adding proper type hints when convenient.

**Why good is better:** The good comment names the specific function, its file and line, the concrete types that should replace `Any`, and confirms how to verify the fix. The worse comment treats type precision as optional polish. `Any` silences mypy for all downstream callers — it is not a mild style issue but a full evacuation of the type system for that function's surface area.
