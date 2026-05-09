# Bash — FP Patterns

Bash-specific patterns for the five FP rules in SKILL.md. Assumes `set -euo pipefail`.

## 1. Pipe Composition

Express multi-step transformations as pipelines of named functions.

**Do:**
```bash
parse_csv()    { cut -d',' -f1; }
strip_blanks() { grep -v '^[[:space:]]*$'; }
uppercase()    { tr '[:lower:]' '[:upper:]'; }

process_names() { parse_csv | strip_blanks | uppercase; }
```

**Don't:** accumulate into a `result` variable with repeated `result=$(echo "$result" | ...)` — that hides the transformation and is harder to test each stage.

## 2. Immutability — `local -r`

Use `local -r` for any binding assigned once. Documents intent; prevents accidental reassignment.

**Do:**
```bash
normalize_path() {
  local -r raw="$1"
  local -r trimmed="${raw%/}"
  printf '%s\n' "${trimmed:-/}"
}
```

**Don't:** use bare `local path="$1"` and then mutate `path` in the same function — each step should produce a new named binding.

## 3. Higher-Order Functions — map / filter / reduce

Implement the pattern as functions that accept a function name and read stdin line-by-line.

```bash
set -euo pipefail

map_lines() {     # map_lines fn < input
  local -r fn="$1"
  while IFS= read -r line; do "$fn" "$line"; done
}

filter_lines() {  # filter_lines fn < input
  local -r fn="$1"
  while IFS= read -r line; do
    "$fn" "$line" && printf '%s\n' "$line" || true
  done
}

reduce_lines() {  # reduce_lines fn init < input
  local -r fn="$1"; local acc="${2:-}"
  while IFS= read -r line; do acc="$("$fn" "$acc" "$line")"; done
  printf '%s\n' "$acc"
}
```

**Usage:**
```bash
double()   { printf '%d\n' "$(( $1 * 2 ))"; }
positive() { (( $1 > 0 )); }
sum()      { printf '%d\n' "$(( $1 + $2 ))"; }

printf '1\n2\n3\n' | map_lines double      # 2 4 6
printf '1\n-2\n3\n' | filter_lines positive # 1 3
printf '1\n2\n3\n' | reduce_lines sum 0    # 6
```

## 4. Side-Effect Isolation

Keep computation pure; push all I/O to the outermost caller.

**Do:**
```bash
build_report() { local -r name="$1" count="$2"; printf '%s: %d\n' "$name" "$count"; }
write_report()  { build_report "$(hostname)" 42 > "$1"; }
```

**Don't:** mix `printf` output with `> file` redirections inside the same function — a function that both computes and writes cannot be tested without the filesystem.

## 5. Pure Function Conventions

A pure bash function takes positional arguments, prints its result to stdout, and reads no globals.

**Do:**
```bash
slugify() {
  local -r input="$1"
  printf '%s\n' "${input// /-}" | tr '[:upper:]' '[:lower:]'
}
```

**Don't:** write results into global variables (`SLUG=...`) and expect callers to read them — use stdout so callers capture with `$()`.

## 6. Command-Query Separation

A function either prints data (query) or causes an effect (command) — not both.

**Do:**
```bash
user_exists() { local -r n="$1"; getent passwd "$n" > /dev/null; }  # query
create_user()  { local -r n="$1"; useradd "$n"; }                    # command
```

**Don't:**
```bash
ensure_user() {
  useradd "$1" 2>/dev/null || true   # command
  id -u "$1"                         # query — mixed
}
```
