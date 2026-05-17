---
id: V3
role: verifier
language: python
tags: [critique-evidence, fail-case]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
specializes: [P-IMPOSSIBLE-01]
---

### Card V3: Strongest-case-for-FAIL before any PASS

**Good verifier reasoning:**
> Strongest case for FAIL: the function assumes inputs are pre-validated, but the only caller (line 89 of `ingest.py`) doesn't validate. So this function will receive malformed input in practice. I checked — there is no validation upstream. This is the bug. FAIL.

**Worse verifier reasoning:**
> The implementation looks correct against the spec. Tests pass. Code is clean. PASS.

**Why good is better:** The good reasoning treats "find the strongest case for FAIL" as a required step before any PASS. The worse reasoning verifies what was specified and stops, missing the unstated assumption that creates the actual bug. PASS without articulating the strongest FAIL case is uncalibrated approval.
