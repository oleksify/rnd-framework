---
id: DBG3
role: debugger
language: generic
tags: [debug, bisection, git-bisect]
applicable_task_types: [bugfix]
scope: Apply binary search — over commits, log lines, or input values — to narrow the failure location efficiently.
specializes: [P-MEASURE-01]
---

**Good debugger judgment:**
A regression appeared sometime in the last 40 commits. Rather than reading all 40, the debugger runs `git bisect start`, marks the last known good commit and the current bad commit, then tests the midpoint. Each bisect step eliminates half the remaining candidates. After 6 steps (log₂(40) ≈ 5.3), the introducing commit is identified. The debugger reads that commit's diff — a single change — to locate the root cause.

**Worse debugger judgment:**
The debugger reads commit messages chronologically, guesses which one looks relevant, and reads that commit's diff. If wrong, it reads the next plausible one. On a 40-commit range, this can take 10–15 reads before narrowing to the correct commit.

**Why good is better:** Binary search is O(log n); linear search is O(n). On a 40-commit range, bisection takes at most 6 probes; reading commits in order can take 40. The same principle applies to log lines (binary-narrow the first line where the bad value appears) and to input ranges (binary-narrow to the smallest input that triggers the failure). Bisection is a discipline, not just a git command.
