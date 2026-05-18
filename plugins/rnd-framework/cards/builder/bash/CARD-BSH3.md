---
id: BSH3
role: builder
language: bash
tags: [portability, paths]
applicable_task_types: [new-feature, infra, refactor]
scope: Resolve the script's own directory with `cd "$(dirname "${BASH_SOURCE[0]}")" && pwd` so relative paths work regardless of where the script is invoked from.
specializes: [P-EFFECTS-EDGE-01]
---

**Good:**
```bash
#!/usr/bin/env bash
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCRIPT_DIR/../lib/helpers.sh"
CONFIG="$_SCRIPT_DIR/../config/defaults.env"
```

**Worse:**
```bash
#!/usr/bin/env bash
set -euo pipefail

source ../lib/helpers.sh
CONFIG=../config/defaults.env
```

**Worse (using $0):**
```bash
_DIR="$(dirname "$0")"
source "$_DIR/../lib/helpers.sh"
```

**Why good is better:** Relative paths like `../lib/helpers.sh` are resolved from the working directory, not the script's location — invoking the script from a different directory silently loads the wrong file or fails. `$0` can be a symlink or a relative path that doesn't point where you think. `${BASH_SOURCE[0]}` is always the real script file; the `cd && pwd` idiom canonicalizes it to an absolute path. Store the result in `_SCRIPT_DIR` once and use it throughout.
