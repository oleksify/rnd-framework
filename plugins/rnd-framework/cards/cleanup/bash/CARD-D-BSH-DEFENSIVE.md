---
id: D-BSH-DEFENSIVE
role: cleanup
language: bash
tags: [dead-code, defensive-programming]
applicable_task_types: [refactor]
scope: Remove manual `$?` checks and redundant exit guards that duplicate what `set -e` already enforces.
specializes: [P-IMPOSSIBLE-01]
---

**Before:**
```bash
#!/usr/bin/env bash
set -euo pipefail

run_migration
if [[ $? -ne 0 ]]; then
  echo "migration failed" >&2
  exit 1
fi

apply_fixtures
rc=$?
if [[ $rc -ne 0 ]]; then
  exit $rc
fi
```

**After:**
```bash
#!/usr/bin/env bash
set -euo pipefail

run_migration
apply_fixtures
```

**Why after is better:** `set -e` already stops execution the moment any command exits non-zero. The `$?` checks and `exit 1` guards are unreachable dead code — if `run_migration` fails, `set -e` aborts before the `if` is evaluated. The guards give false confidence ("I handle errors here") while adding noise that obscures the actual logic. Verify the script has `set -euo pipefail` at the top, then remove every post-command `$?` check that adds no extra context or recovery.
