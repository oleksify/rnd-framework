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
- Don't use `for`/`while`/`until` loops in the Bash tool — they hang. Use the Glob tool to list files by pattern and the Grep tool to search content. For cross-referencing multiple items, use Grep with alternation patterns or multiple parallel tool calls

## Error Handling

- Don't wrap every command in `if ! command; then echo "failed"; exit 1; fi` — `set -e` already exits on failure
- Use `trap 'cleanup' EXIT` for cleanup, not manual cleanup before every exit point
- Don't add retry loops unless the operation is genuinely transient (network calls, lock contention)

## Naming

- Use full words, not abbreviations — `destination` not `dst`, `process_file` not `proc_f`
- Name functions after what they do, not how — `send_notification` not `run_curl_loop`
- Don't use magic numbers — assign them to `readonly` variables with descriptive names

## Function Design

- Keep functions under ~30 lines — if it's longer, it's doing too much
- Do one thing per function — if you need "and" to describe what it does, split it
- Prefer 0–2 parameters; more than 3 is a sign the function needs decomposing
- Don't use flag parameters (`process_file 1` vs `process_file 0`) — write two named functions instead

## Comments

- Write self-explanatory code — a comment that restates what the code does adds no value
- Explain intent and non-obvious constraints, not mechanism — `# retry: S3 returns 503 during deploys`
- Remove commented-out code — use git history instead

## Code Smells

- Duplication across functions or scripts — extract a shared helper rather than copy-pasting
- Global mutable state — functions that set globals are hard to test and compose; use `local` and stdout
- Deep nesting (3+ levels of `if`/`for`) — extract inner blocks into named functions
- Long parameter lists — group related values or restructure the calling code

## Polish

- Order functions by abstraction level: the main entry point first, low-level helpers at the bottom — readers should be able to read top-to-bottom without scrolling back up for context
- Stick to one naming pattern per script: `verb_noun` (`send_report`, `parse_args`) or `noun_verb` — don't mix conventions mid-file
- Comment placement: one comment per non-obvious block, placed above the block — don't interleave inline comments with code when a block comment would be clearer
