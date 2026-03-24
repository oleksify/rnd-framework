#!/usr/bin/env bash
# tests/write-gate.test.sh — Tests for hooks/write-gate.sh
# Usage: bash tests/write-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/write-gate.sh"

PASS=0
FAIL=0

run_hook() {
  local stdin_json="$1"
  HOOK_STDOUT=""
  HOOK_STDERR=""
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$stdin_json" | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

assert_exit() {
  local name="$1" expected="$2"
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then pass "$name"; else fail "$name" "expected exit $expected, got $HOOK_EXIT"; fi
}

assert_stdout_contains() {
  local name="$1" needle="$2"
  if [[ "$HOOK_STDOUT" == *"$needle"* ]]; then pass "$name"; else fail "$name" "expected stdout to contain '$needle', got: '$HOOK_STDOUT'"; fi
}

assert_stdout_empty() {
  local name="$1"
  if [[ -z "$HOOK_STDOUT" ]]; then pass "$name"; else fail "$name" "expected empty stdout, got: '$HOOK_STDOUT'"; fi
}

assert_stderr_contains() {
  local name="$1" needle="$2"
  if [[ "$HOOK_STDERR" == *"$needle"* ]]; then pass "$name"; else fail "$name" "expected stderr to contain '$needle', got: '$HOOK_STDERR'"; fi
}

# ---------------------------------------------------------------------------
# .rnd/ paths → allow JSON, exit 0
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/Users/alice/.claude/.rnd/builds/T1-manifest.md"}}'
assert_exit   ".rnd/ Write path → exit 0" 0
assert_stdout_contains ".rnd/ Write path → allow JSON" '"permissionDecision":"allow"'

run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/Users/alice/.claude-personal/.rnd/sessions/20260101/plan.md"}}'
assert_exit   ".rnd/ Edit path → exit 0" 0
assert_stdout_contains ".rnd/ Edit path → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# Non-.rnd/ paths → no opinion (empty stdout), exit 0
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/Users/alice/Developer/project/src/main.ts"}}'
assert_exit   "regular path → exit 0" 0
assert_stdout_empty "regular path → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# /tmp paths → blocked (exit 2, stderr contains "/tmp")
# ---------------------------------------------------------------------------

# T2 Criterion: Write to /tmp/somefile.txt is blocked
run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/somefile.txt"}}'
assert_exit   "/tmp Write → exit 2" 2
assert_stderr_contains "/tmp Write → stderr contains /tmp" "/tmp"

# T2 Criterion: Edit to /tmp/script.py is blocked
run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/script.py"}}'
assert_exit   "/tmp Edit → exit 2" 2
assert_stderr_contains "/tmp Edit → stderr contains /tmp" "/tmp"

# T2 Criterion: Write to /tmp/deep/nested/file.txt is blocked
run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/deep/nested/file.txt"}}'
assert_exit   "/tmp nested path → exit 2" 2
assert_stderr_contains "/tmp nested path → stderr contains /tmp" "/tmp"

# T2 Edge case: /tmpfoo/bar does NOT match (doesn't start with /tmp/)
run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmpfoo/bar.txt"}}'
assert_exit   "/tmpfoo/ path → exit 0" 0
assert_stdout_empty "/tmpfoo/ path → empty stdout (no opinion)"

# T2 Edge case: exactly /tmp (no trailing slash) — no opinion, it's a directory
run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp"}}'
assert_exit   "/tmp exact → exit 0" 0
assert_stdout_empty "/tmp exact → empty stdout (no opinion)"

# Plugin cache write is NOT auto-allowed (write-gate only allows .rnd/)
run_hook '{"tool_name":"Write","tool_input":{"file_path":"/Users/alice/.claude-personal/plugins/cache/foo/bar.ts"}}'
assert_exit   "plugin cache path → exit 0" 0
assert_stdout_empty "plugin cache path → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# Malformed stdin → exit 0, no crash
# ---------------------------------------------------------------------------

run_hook 'not valid json'
assert_exit   "malformed stdin → exit 0" 0

printf '' | "$HOOK" >/dev/null 2>/dev/null
HOOK_EXIT=$?
if [[ "$HOOK_EXIT" -eq 0 ]]; then pass "empty stdin → exit 0"; else fail "empty stdin → exit 0" "got $HOOK_EXIT"; fi

run_hook '{}'
assert_exit   "empty JSON object → exit 0" 0

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
