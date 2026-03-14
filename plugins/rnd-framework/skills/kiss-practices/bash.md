# Bash — KISS Rules

## Script Structure

- Start with `set -euo pipefail` — don't add custom error trapping unless you need cleanup beyond what `trap` provides
- Don't create bash "frameworks" with option parsers, logging libraries, or plugin systems — if the script is that complex, use a real language
- Don't split a simple script into multiple sourced files — one file is easier to read, copy, and debug
- Don't add `usage()` functions for scripts with 1-2 arguments — a comment at the top is enough

## Variables and Quoting

- Always double-quote variables — `"$var"` not `$var`; the exceptions (glob patterns, intentional splitting) should be commented
- Use `local` in functions — don't pollute the global scope
- Don't use `ALLCAPS` for local variables — reserve ALLCAPS for environment variables and constants
- Use `readonly` for constants instead of `declare -r` — it's shorter and clearer
- Don't use arrays when a simple loop over arguments or lines works — arrays add complexity in bash

## Conditionals and Control Flow

- Use `[[ ]]` not `[ ]` — double brackets handle quoting and patterns better; don't mix styles
- Don't add `else` branches that just echo an error and exit — let `set -e` handle it
- Use `&&` and `||` for simple one-liners — don't wrap a single command in `if/then/fi`
- Don't use `case` for 2 options — `if/elif` is clearer when there are few branches

## Pipelines and Commands

- Use `$(command)` not backticks — backticks don't nest and are harder to read
- Don't pipe to `grep | awk | sed` when a single `awk` or `sed` does the job
- Don't use `cat file | grep` — use `grep pattern file` directly
- Don't add `2>/dev/null` to silence errors you should be fixing
- Use `mktemp` for temp files — don't hardcode `/tmp/myscript.tmp`

## Error Handling

- Don't wrap every command in `if ! command; then echo "failed"; exit 1; fi` — `set -e` already exits on failure
- Use `trap 'cleanup' EXIT` for cleanup, not manual cleanup before every exit point
- Don't add retry loops unless the operation is genuinely transient (network calls, lock contention)
