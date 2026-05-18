---
id: D-BSH-IMPORTS
role: cleanup
language: bash
tags: [dead-code, paths]
applicable_task_types: [refactor]
scope: Remove PATH wrapper scripts for helpers that no longer exist or have been inlined into their callers.
specializes: [P-SMALL-MODULES-01]
---

**Before:**
```bash
# bin/run-audit (a thin $PATH wrapper kept after the helper was deleted)
#!/usr/bin/env bash
exec "$(dirname "$0")/../scripts/audit-runner.sh" "$@"
```
```
$ ls scripts/
# audit-runner.sh is gone — merged into deploy.sh three commits ago
```

**After:**
```
# bin/run-audit is deleted
# Callers updated to invoke deploy.sh --audit directly
```

**Why after is better:** A wrapper for a deleted script fails at runtime, not at the point of the structural mistake. The indirection also hides the deletion from reviewers — the `bin/` entry looks healthy until someone actually runs it. Confirm the target is gone with `ls` or `git log -- scripts/audit-runner.sh`; then delete the wrapper and grep for callers to update them directly. One less file, one less lie in the repo.
