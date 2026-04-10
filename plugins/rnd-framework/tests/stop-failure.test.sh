#!/usr/bin/env bash
# tests/stop-failure.test.sh — Tests for hooks/stop-failure.sh
# Usage: bash tests/stop-failure.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/stop-failure.sh"
RND_DIR_SH="${SCRIPT_DIR}/../lib/rnd-dir.sh"

PASS=0
FAIL=0

run_hook() {
  local stdin_json="$1"
  local env_vars="${2:-}"
  HOOK_STDOUT=""
  HOOK_STDERR=""
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  if [[ -n "$env_vars" ]]; then
    printf '%s' "$stdin_json" | env $env_vars "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  else
    printf '%s' "$stdin_json" | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  fi
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

# ---------------------------------------------------------------------------
# Always exits 0 and emits advisory JSON
# ---------------------------------------------------------------------------

run_hook '{"error_type":"rate_limit","message":"Too many requests"}'
assert_exit "stop-failure → always exits 0" 0
assert_stdout_contains "stop-failure → emits advisory JSON" '"systemMessage"'
assert_stdout_contains "stop-failure → advisory mentions rate limit or retry" "Wait a moment"

run_hook '{}'
assert_exit "empty JSON → exits 0" 0
assert_stdout_contains "empty JSON → still emits advisory" '"systemMessage"'

run_hook 'not json'
assert_exit "malformed stdin → exits 0" 0

printf '' | "$HOOK" >/dev/null 2>/dev/null
HOOK_EXIT=$?
if [[ "$HOOK_EXIT" -eq 0 ]]; then pass "empty stdin → exits 0"; else fail "empty stdin → exits 0" "got $HOOK_EXIT"; fi

# Advisory output is valid JSON
run_hook '{"error_type":"auth_error","message":"Unauthorized"}'
if printf '%s' "$HOOK_STDOUT" | jq . > /dev/null 2>&1; then
  pass "advisory output is valid JSON"
else
  fail "advisory output is valid JSON" "got: '$HOOK_STDOUT'"
fi

# ---------------------------------------------------------------------------
# Writes stop-failures.jsonl to active session when one exists
# ---------------------------------------------------------------------------

tmp_config="$(mktemp -d)"
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" "$RND_DIR_SH" --base 2>/dev/null || true)"
if [[ -n "$base_dir" ]]; then
  session_id="20260101-120000-abcd"
  session_dir="${base_dir}/sessions/${session_id}"
  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_dir}/.current-session"

  run_hook '{"error_type":"rate_limit","message":"Rate limited"}' "CLAUDE_CONFIG_DIR=${tmp_config}"
  assert_exit "stop-failure with active session → exits 0" 0

  if [[ -f "${session_dir}/stop-failures.jsonl" ]]; then
    pass "stop-failures.jsonl is created in session directory"
    entry="$(head -1 "${session_dir}/stop-failures.jsonl")"
    if printf '%s' "$entry" | jq . > /dev/null 2>&1; then
      pass "stop-failures.jsonl entry is valid JSON"
    else
      fail "stop-failures.jsonl entry is valid JSON" "got: '$entry'"
    fi
    if [[ "$entry" == *'"rate_limit"'* ]]; then
      pass "stop-failures.jsonl entry contains error_type"
    else
      fail "stop-failures.jsonl entry contains error_type" "got: '$entry'"
    fi
    if [[ "$entry" == *'"Rate limited"'* ]]; then
      pass "stop-failures.jsonl entry contains the message"
    else
      fail "stop-failures.jsonl entry contains the message" "got: '$entry'"
    fi
  else
    fail "stop-failures.jsonl is created in session directory" "not found"
    fail "stop-failures.jsonl entry is valid JSON" "(skipped)"
    fail "stop-failures.jsonl entry contains error_type" "(skipped)"
    fail "stop-failures.jsonl entry contains the message" "(skipped)"
  fi
else
  fail "rnd-dir.sh --base resolved" "(rnd-dir.sh failed; skipping jsonl tests)"
  fail "stop-failures.jsonl is created in session directory" "(skipped)"
  fail "stop-failures.jsonl entry is valid JSON" "(skipped)"
  fail "stop-failures.jsonl entry contains error_type" "(skipped)"
  fail "stop-failures.jsonl entry contains the message" "(skipped)"
fi

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
