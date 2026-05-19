#!/usr/bin/env bash
# tests/orchestrator-briefs-read.test.sh — Verifies that the orchestrator (empty
# agent_type) can read briefs/ and self-assessment artifacts, while rnd-verifier
# remains blocked.
# Usage: bash tests/orchestrator-briefs-read.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/read-gate.sh"

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

pass() {
  printf 'PASS  %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf 'FAIL  %s — %s\n' "$1" "$2"
  FAIL=$((FAIL + 1))
}

assert_exit() {
  local name="$1" expected="$2"
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expected, got $HOOK_EXIT"
  fi
}

BRIEFS_PATH="/Users/someone/.claude/.rnd/claude-abc/branches/main/sessions/20260518-090000-abcd/briefs/plan-briefs.md"

# Orchestrator (empty agent_type) reading a briefs/ artifact → must be allowed (exit 0)
run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${BRIEFS_PATH}\"},\"agent_type\":\"\"}"
assert_exit "empty agent_type + briefs/ path → exit 0 (orchestrator allowed)" 0

# rnd-verifier reading the same briefs/ path → must be blocked (exit 2)
run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${BRIEFS_PATH}\"},\"agent_type\":\"rnd-verifier\"}"
assert_exit "rnd-verifier + briefs/ path → exit 2 (barrier enforced)" 2

# rnd-polisher reading a briefs/ path → must also be blocked (exit 2)
run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${BRIEFS_PATH}\"},\"agent_type\":\"rnd-polisher\"}"
assert_exit "rnd-polisher + briefs/ path → exit 2 (barrier enforced)" 2

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
