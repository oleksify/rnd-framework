---
id: PYT2
role: verifier
language: python
tags: [critique-evidence, fail-case, validation]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Parametrize coverage must include boundary cases — empty, single element, zero, and negative — not just happy-path values.
specializes: [P-IMPOSSIBLE-01]
---

Specializes the impossible-states principle by requiring that parametrized tests exercise boundary inputs: the cases the implementation is most likely to mishandle are empty collections, single elements, and out-of-range values.

**Good review comment:**
> FAIL. `test_median` is parametrized with `[2, 3, 5]` — all interior positive values. The implementation is untested on: empty list (raises or returns?), single element (off-by-one index risk), zero (neutral value that can mask sign errors), and negative values (sorting assumption). Add at minimum `[]`, `[7]`, `[0]`, and `[-3, 1]` as parameter cases. The current suite proves the happy path only.

**Worse review comment:**
> The test covers several numeric inputs. Parametrize looks correct for the described behavior.

**Why good is better:** The good comment names the four missing boundary classes and explains why each matters. The worse comment confirms that parametrize syntax is correct — a structural check, not a coverage check. Boundary inputs are exactly the cases where implementations diverge from intent; a parametrized suite that only exercises interior values gives false confidence.
