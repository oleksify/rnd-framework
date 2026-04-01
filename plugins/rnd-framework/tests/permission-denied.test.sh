#!/usr/bin/env bash
# Tests for hooks/permission-denied.sh
# Usage: bash tests/permission-denied.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/permission-denied.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Setup: create a temporary active session for audit logging tests
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
mkdir -p "$TMP_SESSION"
printf '20260401-120000-abcd' > "${TMP_BASE}/.current-session"

# Cache the base dir (session-start.sh normally does this)
mkdir -p "${TMP_CONFIG}/.rnd"
printf '%s' "$TMP_BASE" > "${TMP_CONFIG}/.rnd/.active-base-dir"

# ---------------------------------------------------------------------------
# Test: returns retry JSON
# ---------------------------------------------------------------------------
printf '%s\n' '--- permission-denied: retry response ---'

run_hook "$HOOK" '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
assert_exit_code "returns exit 0" 0
assert_contains "stdout contains retry:true" '"retry":true' "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: handles missing tool_name gracefully
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- permission-denied: missing tool_name ---'

run_hook "$HOOK" '{"tool_input":{"command":"something"}}'
assert_exit_code "missing tool_name → exit 0" 0
assert_contains "still returns retry" '"retry":true' "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: handles empty/malformed input
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- permission-denied: malformed input ---'

run_hook "$HOOK" ''
assert_exit_code "empty input → exit 0" 0
assert_contains "empty input → retry" '"retry":true' "$HOOK_STDOUT"

run_hook "$HOOK" 'not json'
assert_exit_code "non-JSON input → exit 0" 0
assert_contains "non-JSON → retry" '"retry":true' "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: audit log written when active session exists
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- permission-denied: audit logging ---'

# Run with CLAUDE_CONFIG_DIR pointing to our temp config
HOOK_EXIT=0
tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
printf '%s' '{"tool_name":"Edit","tool_input":{}}' \
  | CLAUDE_CONFIG_DIR="$TMP_CONFIG" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$tmp_out")"; HOOK_STDERR="$(cat "$tmp_err")"
rm -f "$tmp_out" "$tmp_err"

assert_exit_code "with active session → exit 0" 0
assert_contains "with active session → retry" '"retry":true' "$HOOK_STDOUT"

# Check audit.jsonl was created and contains the entry
if [[ -f "${TMP_SESSION}/audit.jsonl" ]]; then
  last_entry="$(tail -1 "${TMP_SESSION}/audit.jsonl")"
  assert_contains "audit entry contains permission_denied event" '"permission_denied"' "$last_entry"
  assert_contains "audit entry contains tool name" '"Edit"' "$last_entry"
else
  assert_eq "audit.jsonl was created" "exists" "missing"
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$TMP_CONFIG"

report
