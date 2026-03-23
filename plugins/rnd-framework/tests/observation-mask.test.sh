#!/usr/bin/env bash
# tests/observation-mask.test.sh — Tests for hooks/observation-mask.sh
# Usage: bash tests/observation-mask.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/observation-mask.sh"
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

assert_stdout_empty() {
  local name="$1"
  if [[ -z "$HOOK_STDOUT" ]]; then pass "$name"; else fail "$name" "expected empty stdout, got: '$HOOK_STDOUT'"; fi
}

assert_stdout_contains() {
  local name="$1" needle="$2"
  if [[ "$HOOK_STDOUT" == *"$needle"* ]]; then pass "$name"; else fail "$name" "expected stdout to contain '$needle', got: '$HOOK_STDOUT'"; fi
}

# ---------------------------------------------------------------------------
# No active session → exits 0 immediately with no output
# ---------------------------------------------------------------------------

# Without an active session, the hook short-circuits at `active_session_dir || exit 0`
run_hook '{"stdout":"line1\nline2"}'
assert_exit "no active session → exits 0" 0
assert_stdout_empty "no active session → empty stdout (short-circuit)"

run_hook '{}'
assert_exit "no active session, empty JSON → exits 0" 0

# ---------------------------------------------------------------------------
# With an active session: output below threshold → no advisory
# ---------------------------------------------------------------------------

tmp_config="$(mktemp -d)"
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -n "$base_dir" ]]; then
  session_id="20260101-120000-abcd"
  session_dir="${base_dir}/sessions/${session_id}"
  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_dir}/.current-session"

  # Build a small stdout payload (under 50 lines)
  small_stdout="$(printf 'line %d\n' {1..10} | tr '\n' '\\n')"
  run_hook "{\"stdout\":\"$(printf 'line %d\n' {1..10})\"}" "CLAUDE_CONFIG_DIR=${tmp_config}"
  assert_exit "stdout under threshold with session → exits 0" 0
  assert_stdout_empty "stdout under threshold → no advisory emitted"

  # Build a large stdout payload (over 50 lines)
  large_stdout="$(seq 1 55 | sed 's/^/line /')"
  large_json="$(jq -cn --arg s "$large_stdout" '{"stdout":$s}')"
  run_hook "$large_json" "CLAUDE_CONFIG_DIR=${tmp_config}"
  assert_exit "stdout over threshold with session → exits 0" 0
  assert_stdout_contains "stdout over threshold → advisory emitted" '"additionalContext"'
  assert_stdout_contains "stdout over threshold → advisory mentions line count" "55"

  # Advisory is valid JSON
  if printf '%s' "$HOOK_STDOUT" | jq . > /dev/null 2>&1; then
    pass "advisory output is valid JSON"
  else
    fail "advisory output is valid JSON" "got: '$HOOK_STDOUT'"
  fi

  # Empty stdout field → no advisory (short-circuit before line count)
  run_hook '{"stdout":""}' "CLAUDE_CONFIG_DIR=${tmp_config}"
  assert_exit "empty stdout field → exits 0" 0
  assert_stdout_empty "empty stdout field → no advisory"

else
  fail "rnd-dir.sh --base resolved" "(rnd-dir.sh failed; skipping session tests)"
  fail "stdout under threshold with session → exits 0" "(skipped)"
  fail "stdout under threshold → no advisory emitted" "(skipped)"
  fail "stdout over threshold with session → exits 0" "(skipped)"
  fail "stdout over threshold → advisory emitted" "(skipped)"
  fail "stdout over threshold → advisory mentions line count" "(skipped)"
  fail "advisory output is valid JSON" "(skipped)"
  fail "empty stdout field → exits 0" "(skipped)"
  fail "empty stdout field → no advisory" "(skipped)"
fi

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
