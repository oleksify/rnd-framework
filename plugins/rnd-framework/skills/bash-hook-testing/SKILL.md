---
name: bash-hook-testing
description: "Use when writing or modifying tests for rnd-framework hook scripts — covers the test-helpers.sh framework, run_hook pattern, assertions, environment mocking, and test organization"
effort: low
---

# Bash Hook Testing

## Overview

Every hook script in `hooks/` has a corresponding test file in `tests/`. Tests use a custom framework (`test-helpers.sh`) that provides stdin-driven hook invocation, assertion helpers, and a pass/fail report. No external test runners are needed — each test file is a standalone bash script.

## Test File Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"

HOOK="${SCRIPT_DIR}/../hooks/<hook-name>.sh"

printf '%s\n' '--- Section Name ---'

# Test: description
run_hook "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/some/path"}}'
assert_exit_code "description of expected exit code" 0
assert_eq "description of expected stdout" '{"hookSpecificOutput":...}' "$HOOK_STDOUT"

# ... more tests ...

report
```

Key points:
- File naming: `<hook-name>.test.sh` (e.g., `read-gate.test.sh`)
- Always call `report` at the end — it prints summary and exits 1 if any test failed
- Group related tests with `printf '%s\n' '--- Section Name ---'` headers

## Test Helpers API

### run_hook

```bash
run_hook "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/foo"}}'
```

Feeds the JSON string as stdin to the hook script. After execution, three variables are set:

| Variable | Content |
|---|---|
| `HOOK_STDOUT` | Everything the hook printed to stdout |
| `HOOK_STDERR` | Everything the hook printed to stderr |
| `HOOK_EXIT` | The exit code (0, 2, etc.) |

### Assertions

```bash
assert_eq "description" "expected" "$actual"
assert_contains "description" "needle" "$haystack"
assert_exit_code "description" 0
```

- `assert_eq` — exact string match
- `assert_contains` — substring match (useful for JSON or error messages)
- `assert_exit_code` — checks `$HOOK_EXIT` against expected code

### report

```bash
report
```

Prints `N pass, M fail (T total)` and returns exit code 1 if any test failed. Must be the last call in every test file.

## Testing the Three Decision Paths

Every PreToolUse hook should be tested for all three outcomes:

### 1. Auto-allow (exit 0 + allow JSON)

```bash
run_hook "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/session/plan.md"}}'
assert_exit_code "auto-allows .rnd/ path" 0
assert_contains "auto-allows .rnd/ path stdout" "allow" "$HOOK_STDOUT"
```

### 2. Block (exit 2 + stderr message)

```bash
run_hook "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/path/to/self-assessment.md"},"agent_type":"verifier"}'
assert_exit_code "blocks self-assessment read" 2
assert_contains "block message" "INFORMATION BARRIER" "$HOOK_STDERR"
```

### 3. No opinion (exit 0 + empty stdout)

```bash
run_hook "$HOOK" '{"tool_name":"Read","tool_input":{"file_path":"/some/regular/file.ts"}}'
assert_exit_code "no opinion for regular file" 0
assert_eq "no opinion produces no stdout" "" "$HOOK_STDOUT"
```

## Environment Mocking

### Setting CLAUDE_PLUGIN_ROOT

Some hooks use `CLAUDE_PLUGIN_ROOT` to locate resources:

```bash
export CLAUDE_PLUGIN_ROOT="${SCRIPT_DIR}/.."
```

### Creating Temp Session State

For hooks that check `active_session_dir`:

```bash
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export CLAUDE_CONFIG_DIR="$TMP_DIR"
mkdir -p "$TMP_DIR/.rnd/test-project/sessions/20260101-120000-abcd1234"
printf '%s' "20260101-120000-abcd1234" > "$TMP_DIR/.rnd/test-project/.current-session"
```

### Testing Fast-Path Exit

Hooks with `active_session_dir` fast-path should be tested without a session:

```bash
unset CLAUDE_CONFIG_DIR
run_hook "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
assert_exit_code "exits cleanly without active session" 0
assert_eq "no output without active session" "" "$HOOK_STDOUT"
```

## Testing lib.sh Functions

For lib.sh utility functions, source lib.sh directly instead of using `run_hook`:

```bash
source "${SCRIPT_DIR}/../hooks/lib.sh"

result="$(jq_extract '{"key":"val"}' '.key')"
assert_eq "jq_extract extracts field" "val" "$result"
```

See `tests/lib-fp.test.sh` for the canonical pattern.

## Running Tests

```bash
cd plugins/rnd-framework
bash tests/run-tests.sh
```

This runs all `*.test.sh` files in `tests/` and reports any failures. Individual tests can be run directly:

```bash
bash tests/read-gate.test.sh
```

## Coverage Expectations

- Every hook script in `hooks/` should have a corresponding `tests/<name>.test.sh`
- Test all decision paths (allow, block, no-opinion, advisory)
- Test edge cases: empty input, missing fields, malformed JSON
- Test platform-specific tool names (`Write` vs `Create` vs `write`)

## Related Skills

- `rnd-framework:hook-authoring` — how hooks work and how to write them
- `rnd-framework:lib-sh-patterns` — the shared functions being tested
