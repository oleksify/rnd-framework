---
id: BSH1
role: builder
language: bash
tags: [error-handling, defensive-programming]
applicable_task_types: [new-feature, infra, refactor]
scope: Set `set -euo pipefail` at the top of every script; do not add manual error checks for what `-e` already catches.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```bash
#!/usr/bin/env bash
set -euo pipefail

parse_input "$1"
transform_data "$TMPFILE"
write_output "$OUTDIR"
```

**Worse:**
```bash
#!/usr/bin/env bash

parse_input "$1"
if [[ $? -ne 0 ]]; then
  echo "parse failed" >&2
  exit 1
fi
transform_data "$TMPFILE"
if [[ $? -ne 0 ]]; then
  echo "transform failed" >&2
  exit 1
fi
```

**Why good is better:** Without `set -e`, a failing command silently passes control to the next line; the script continues in a broken state. The worse version compensates with `$?` guards after every call — noise that still misses error paths inside subshells. `set -euo pipefail` makes failure loud at the point it occurs: `-e` stops on any non-zero exit, `-u` treats unset variables as errors, and `-o pipefail` propagates failures through pipes. Drop the manual guards; let the shell enforce the invariant.
