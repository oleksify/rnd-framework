---
name: hook-authoring
description: "Use when writing or modifying rnd-framework hook scripts — covers hook anatomy, exit code protocol, stdin parsing, fast-path patterns, hooks.json registration, and multi-platform tool matchers"
effort: low
---

# Hook Authoring

## Overview

rnd-framework hooks are bash scripts invoked by Claude Code, Factory Droid, and OpenCode at specific lifecycle points. Every hook follows a strict contract: it reads JSON from stdin, makes a decision, and communicates it via exit code + stdout/stderr. Breaking this contract silently breaks the pipeline.

## Hook Anatomy

Every PreToolUse hook follows this skeleton:

```bash
#!/usr/bin/env bash
# hooks/<name>.sh — <One-line purpose>.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_input
file_path="$(extract_file_path "$TOOL_INPUT")"

# Decision logic here...

exit 0
```

Key points:
- `set -euo pipefail` is inherited from `lib.sh` — never add it again
- Always source `lib.sh` via `BASH_SOURCE[0]` — never use `$0` (breaks under sourcing)
- Use `parse_input` for PreToolUse hooks (sets `TOOL_NAME`, `TOOL_INPUT`, `AGENT_TYPE`)
- Use raw `jq` extraction for PostToolUse/event hooks (different stdin schema)

## Exit Code Contract

| Exit Code | Stdout | Stderr | Meaning |
|---|---|---|---|
| `0` | `allow_json` output | — | Auto-allow the tool operation |
| `0` | `advisory_json "msg"` output | — | Warn but allow |
| `0` | nothing | — | No opinion (default permission prompt) |
| `2` | — | `block_msg "reason"` | Block the operation |

Any other exit code is treated as a hook failure and logged. Never use `exit 1` for blocking — that signals a script error, not a policy decision.

## Response Functions

From `lib.sh`:

```bash
allow_json          # Prints allow JSON to stdout
advisory_json "msg" # Prints advisory JSON (jq-escapes the message)
block_msg "reason"  # Prints to stderr and exits 2
```

Never construct JSON manually — these functions handle escaping and format.

## Stdin Parsing

### PreToolUse hooks

Use `parse_input` which reads all of stdin and sets three globals:

```bash
parse_input
# Now available: $TOOL_NAME, $TOOL_INPUT (JSON string), $AGENT_TYPE
```

Extract specific fields from `TOOL_INPUT`:

```bash
file_path="$(extract_file_path "$TOOL_INPUT")"
command="$(printf '%s' "$TOOL_INPUT" | jq -r '.command // ""' 2>/dev/null || true)"
```

### PostToolUse / event hooks

Read stdin directly — the schema differs (includes `tool_output`):

```bash
raw="$(cat)"
tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null || true)"
```

## Fast-Path Pattern

Hooks that only matter during active pipeline runs should exit early:

```bash
session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0
```

This avoids expensive logic when no RND session is active. The `active_session_dir` function uses a process-level cache and fast-path file reads to minimize overhead (~1ms vs ~15ms for full git+shasum resolution).

## Multi-Platform Tool Name Matchers

hooks.json matchers must cover all three platforms:

| Platform | Bash | Read | Write | Edit | Glob | Grep |
|---|---|---|---|---|---|---|
| Claude Code | `Bash` | `Read` | `Write` | `Edit` | `Glob` | `Grep` |
| Factory Droid | `Bash`, `Execute` | `Read` | `Write`, `Create` | `Edit` | `Glob` | `Grep` |
| OpenCode | `bash` | `read` | `write` | `edit` | `glob` | `grep` |

Matcher patterns in hooks.json: `"Bash|Execute|bash"`, `"Read|read"`, `"Write|Create|write"`, `"Edit|edit"`, etc.

## Registering a New Hook

Add an entry to `hooks.json` under the appropriate event:

```json
{
  "matcher": "ToolName|tool_name",
  "hooks": [
    {
      "type": "command",
      "command": "'${CLAUDE_PLUGIN_ROOT}/hooks/my-hook.sh'"
    }
  ]
}
```

For PostToolUse hooks, prefer extending `post-dispatch.sh` with a new `case` branch rather than adding a separate hook entry — this reduces hook invocation overhead.

## The Post-Dispatch Pattern

`post-dispatch.sh` is a unified PostToolUse handler that dispatches by tool name:

```bash
case "$tool_name" in
  Write|Create|write|Edit|edit)
    # Audit logging
    ;;
  Bash|Execute|bash)
    # Observation mask
    ;;
esac
```

Add new PostToolUse behaviors as additional `case` branches here.

## Common Anti-Patterns

- **Using cat/grep/sed/find inside hooks** — these are blocked by `bash-gate.sh`, the very hook system you're extending. Use `jq` for JSON, `lib.sh` functions for path checks.
- **Forgetting to handle empty stdin** — `parse_input` handles this gracefully (sets empty strings). Raw `jq` calls need `// ""` fallbacks.
- **Not quoting file paths** — paths with spaces break unquoted expansions. Always `"$file_path"`.
- **Using `exit 1` to block** — use `block_msg` (exit 2). Exit 1 means script error.
- **Printing to stdout without a decision** — any stdout is interpreted as hook output. Debug prints go to stderr or nowhere.
- **Not making the script executable** — `chmod +x hooks/my-hook.sh`. The `validate.sh` checks this.

## Checklist for New Hooks

1. Script is executable (`chmod +x`)
2. Sources `lib.sh` via `BASH_SOURCE[0]`
3. Uses `parse_input` (PreToolUse) or raw stdin reading (other events)
4. Returns decisions via `allow_json` / `advisory_json` / `block_msg` / silent exit 0
5. Registered in `hooks.json` with multi-platform matchers
6. Has a corresponding test file in `tests/<hook-name>.test.sh`
7. Passes `validate.sh`

## Related Skills

- `rnd-framework:lib-sh-patterns` — shared utility functions used in hooks
- `rnd-framework:bash-hook-testing` — how to test hook scripts
- `rnd-framework:plugin-architecture` — platform differences affecting hooks
