---
id: D-BSH-DEBUG
role: cleanup
language: bash
tags: [dead-code, debug-artifacts]
applicable_task_types: [refactor]
scope: Delete leftover `set -x` traces and `echo "DEBUG:..."` lines added during iteration before the script ships.
specializes: [P-PURE-RENDER-01]
---

**Before:**
```bash
#!/usr/bin/env bash
set -euo pipefail
set -x   # left on after debugging session

process_records "$INPUT_FILE"

echo "DEBUG: after process_records, status=$?"
write_results "$OUTPUT_DIR"
```

**After:**
```bash
#!/usr/bin/env bash
set -euo pipefail

process_records "$INPUT_FILE"
write_results "$OUTPUT_DIR"
```

**Why after is better:** `set -x` prints every command and expansion to stderr — in production it floods logs, leaks environment variable values, and makes real error output impossible to find. `echo "DEBUG: ..."` lines produce output no caller asked for and cannot be silenced without modifying the script. Both are iteration scaffolding, not part of the script's contract. Scan with `grep -n 'set -x\|echo.*DEBUG' scripts/**/*.sh` before shipping; remove every match.
