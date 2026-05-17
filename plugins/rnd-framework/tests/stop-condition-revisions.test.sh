#!/usr/bin/env bash
# Tests for hooks/stop-condition-revisions.sh
# Usage: bash tests/stop-condition-revisions.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/stop-condition-revisions.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup — mirrors builder-dismissal-gate.test.sh pattern
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
mkdir -p "${TMP_SESSION}/builds"

printf '20260401-120000-abcd' > "${TMP_BASE}/.current-session"
mkdir -p "${TMP_CONFIG}/.rnd"
printf '%s' "$TMP_BASE" > "${TMP_CONFIG}/.rnd/.active-base-dir"

cleanup() {
  rm -rf "$TMP_CONFIG"
}
trap cleanup EXIT

# Helper: run the hook with CLAUDE_CONFIG_DIR pointed at the temp fixture.
# Passes RND_STOP_FILE_REVISIONS if provided.
run_with_session() {
  local stdin_json="$1"
  local threshold_override="${2:-}"
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  if [[ -n "$threshold_override" ]]; then
    printf '%s' "$stdin_json" \
      | env -i PATH="$PATH" HOME="$HOME" \
          CLAUDE_CONFIG_DIR="$TMP_CONFIG" \
          RND_STOP_FILE_REVISIONS="$threshold_override" \
          "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
  else
    printf '%s' "$stdin_json" \
      | env -i PATH="$PATH" HOME="$HOME" \
          CLAUDE_CONFIG_DIR="$TMP_CONFIG" \
          "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
  fi

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# ---------------------------------------------------------------------------
# Test 1: no active session → fast-path exit 0
# ---------------------------------------------------------------------------
printf '%s\n' '--- stop-condition-revisions: no active session → exit 0 ---'

NO_SESSION_DIR="$(mktemp -d)"
rm -rf "$NO_SESSION_DIR"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.sh"}}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$NO_SESSION_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "no active session → exit 0" 0

# ---------------------------------------------------------------------------
# Test 2: file not yet at threshold (4 prior writes, default threshold 5) → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- stop-condition-revisions: 4 writes below threshold → exit 0 ---'

# Write a build manifest so hook can resolve task_id
printf '# Build Manifest: T1\n\nStatus: DONE\n' > "${TMP_SESSION}/builds/T1-manifest.md"

# Populate audit.jsonl with 4 Write events for /p/foo.sh
printf '{"ts":"2026-05-01T10:00:00Z","tool":"Write","file":"/p/foo.sh"}\n' > "${TMP_SESSION}/audit.jsonl"
printf '{"ts":"2026-05-01T10:01:00Z","tool":"Edit","file":"/p/foo.sh"}\n' >> "${TMP_SESSION}/audit.jsonl"
printf '{"ts":"2026-05-01T10:02:00Z","tool":"Write","file":"/p/foo.sh"}\n' >> "${TMP_SESSION}/audit.jsonl"
printf '{"ts":"2026-05-01T10:03:00Z","tool":"Edit","file":"/p/foo.sh"}\n' >> "${TMP_SESSION}/audit.jsonl"

run_with_session '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.sh"}}'
assert_exit_code "4 writes below threshold → exit 0" 0
assert_eq "no stderr on pass-through" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 3: 5th write at threshold (default 5) → exit 2, STOP CONDITION in stderr
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- stop-condition-revisions: 5 writes at threshold → exit 2 ---'

# audit.jsonl already has 4 events, add 1 more so count=5 BEFORE the 5th write is logged
# (the hook counts existing events, then blocks when count >= threshold)
printf '{"ts":"2026-05-01T10:04:00Z","tool":"Write","file":"/p/foo.sh"}\n' >> "${TMP_SESSION}/audit.jsonl"

run_with_session '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.sh"}}'
assert_exit_code "5 writes at threshold → exit 2" 2
assert_contains "stderr contains STOP CONDITION" "STOP CONDITION" "$HOOK_STDERR"
assert_contains "stderr contains RND_STOP_FILE_REVISIONS" "RND_STOP_FILE_REVISIONS" "$HOOK_STDERR"
assert_contains "stderr contains file path" "/p/foo.sh" "$HOOK_STDERR"
assert_contains "stderr contains task id" "T1" "$HOOK_STDERR"
assert_contains "stderr contains threshold value" "5" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 4: threshold override to 10 — 5 prior writes → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- stop-condition-revisions: RND_STOP_FILE_REVISIONS=10 raises threshold → exit 0 ---'

# audit.jsonl still has 5 events from Test 3
run_with_session '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.sh"}}' "10"
assert_exit_code "RND_STOP_FILE_REVISIONS=10 with 5 writes → exit 0" 0

# ---------------------------------------------------------------------------
# Test 5: non-integer threshold → exit 2 with usage error
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- stop-condition-revisions: non-integer threshold → exit 2 ---'

run_with_session '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.sh"}}' "abc"
assert_exit_code "non-integer threshold → exit 2" 2
assert_contains "non-integer threshold error in stderr" "non-negative integer" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 6: file_path absent in stdin → exit 0 (no-opinion)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- stop-condition-revisions: no file_path in stdin → exit 0 ---'

run_with_session '{"tool_name":"Write","tool_input":{}}'
assert_exit_code "no file_path → exit 0" 0

# ---------------------------------------------------------------------------
# Test 7: different file not at threshold → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- stop-condition-revisions: different file unaffected ---'

# audit.jsonl has 5 events for /p/foo.sh; /p/other.sh has 0
run_with_session '{"tool_name":"Write","tool_input":{"file_path":"/p/other.sh"}}'
assert_exit_code "different file → exit 0" 0

# ---------------------------------------------------------------------------
# Test 8: gateFired audit event emitted on halt
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- stop-condition-revisions: gateFired emitted on halt ---'

# audit.jsonl still has 5 events for /p/foo.sh — will trigger block
# Capture state of audit.jsonl before
audit_count_before="$(grep -c '.' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || printf '0')"

run_with_session '{"tool_name":"Write","tool_input":{"file_path":"/p/foo.sh"}}'
assert_exit_code "halt with gateFired → exit 2" 2

audit_count_after="$(grep -c '.' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || printf '0')"
# A new gate_fired event should have been appended
new_lines=$(( audit_count_after - audit_count_before ))

# The gate_fired event should be appended
gate_event_count="$(grep -c '"gate_fired"' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || printf '0')"
HOOK_EXIT=0
HOOK_STDERR=""
HOOK_STDOUT=""
if [[ "$gate_event_count" -gt 0 ]]; then
  HOOK_EXIT=0
  printf '  PASS  gateFired event present in audit.jsonl\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  gateFired event not found in audit.jsonl\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
TESTS_TOTAL=$((TESTS_TOTAL + 1))

# ---------------------------------------------------------------------------
report
