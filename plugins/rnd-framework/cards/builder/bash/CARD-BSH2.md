---
id: BSH2
role: builder
language: bash
tags: [decomposition, performance]
applicable_task_types: [new-feature, infra, refactor]
scope: Replace chains of `grep | grep | sed` with a single `awk` expression that does the filtering and extraction in one pass.
specializes: [P-SMALL-MODULES-01]
---

**Good:**
```bash
# Extract non-comment non-blank key=value pairs from a config file
awk '!/^[[:space:]]*(#|$)/ && /=/ { print $0 }' config.ini
```

**Worse:**
```bash
grep -v '^[[:space:]]*#' config.ini \
  | grep -v '^[[:space:]]*$' \
  | grep '='
```

**Why good is better:** Each `grep` spawns a subprocess and reads the full input stream again. For small files the cost is invisible; for logs or large configs it compounds. More critically, the worse version is hard to extend — adding another filter means another pipe segment and another read. `awk` processes the file in a single pass: patterns compose with `&&`/`||`, actions can extract specific fields, and the result is one process. Reach for `awk` when you need filter + transform in one step.
