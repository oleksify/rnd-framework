#!/usr/bin/env bash
# Tests for /cleanup/ information barrier across read-gate.sh, bash-gate.sh, and glob-grep-gate.sh.
# Usage: bash tests/cleanup-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READ_GATE="${SCRIPT_DIR}/../hooks/read-gate.sh"
BASH_GATE="${SCRIPT_DIR}/../hooks/bash-gate.sh"
GLOB_GREP_GATE="${SCRIPT_DIR}/../hooks/glob-grep-gate.sh"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_hook() {
  local hook="$1"
  local stdin_json="$2"
  HOOK_STDOUT=""
  HOOK_STDERR=""
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$stdin_json" | "$hook" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

pass() {
  local name="$1"
  printf 'PASS  %s\n' "$name"
  PASS=$((PASS + 1))
}

fail() {
  local name="$1"
  local detail="$2"
  printf 'FAIL  %s — %s\n' "$name" "$detail"
  FAIL=$((FAIL + 1))
}

assert_exit() {
  local name="$1"
  local expected="$2"
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expected, got $HOOK_EXIT"
  fi
}

assert_stderr_contains() {
  local name="$1"
  local needle="$2"
  if [[ "$HOOK_STDERR" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected stderr to contain '$needle', got: '$HOOK_STDERR'"
  fi
}

assert_stdout_contains() {
  local name="$1"
  local needle="$2"
  if [[ "$HOOK_STDOUT" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected stdout to contain '$needle', got: '$HOOK_STDOUT'"
  fi
}

assert_stdout_empty() {
  local name="$1"
  if [[ -z "$HOOK_STDOUT" ]]; then
    pass "$name"
  else
    fail "$name" "expected empty stdout, got: '$HOOK_STDOUT'"
  fi
}

CLEANUP_PATH="/home/user/.claude/.rnd/sessions/20260101-120000-abcd/cleanup/T1-cleanup-report.md"

# ---------------------------------------------------------------------------
# read-gate.sh — /cleanup/ barrier
# ---------------------------------------------------------------------------

printf '\n--- read-gate.sh: /cleanup/ barrier ---\n'

# 1. rnd-verifier is blocked
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"'"$CLEANUP_PATH"'"},"agent_type":"rnd-verifier"}'
assert_exit   "read-gate: /cleanup/ + rnd-verifier → exit 2" 2
assert_stderr_contains "read-gate: /cleanup/ + rnd-verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# 2. rnd-integrator is allowed (exits 0, no block)
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"'"$CLEANUP_PATH"'"},"agent_type":"rnd-integrator"}'
assert_exit   "read-gate: /cleanup/ + rnd-integrator → exit 0" 0

# 3. absent agent_type (orchestrator) is allowed — it relays cleanup artifacts to the user
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"'"$CLEANUP_PATH"'"},"agent_type":""}'
assert_exit   "read-gate: /cleanup/ + empty agent_type → exit 0 (orchestrator allowed)" 0

# ---------------------------------------------------------------------------
# bash-gate.sh — /cleanup/ barrier
# ---------------------------------------------------------------------------

printf '\n--- bash-gate.sh: /cleanup/ barrier ---\n'

# 4. rnd-verifier is blocked
run_hook "$BASH_GATE" \
  '{"tool_name":"Bash","tool_input":{"command":"cat '"$CLEANUP_PATH"'"},"agent_type":"rnd-verifier"}'
assert_exit   "bash-gate: cat /cleanup/... + rnd-verifier → exit 2" 2
assert_stderr_contains "bash-gate: cat /cleanup/... + rnd-verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# 5. rnd-integrator is not blocked by the barrier (may still be blocked for other reasons, but not barrier)
run_hook "$BASH_GATE" \
  '{"tool_name":"Bash","tool_input":{"command":"cat '"$CLEANUP_PATH"'"},"agent_type":"rnd-integrator"}'
# cat is a read command — bash-gate allows it; barrier doesn't apply to integrator
assert_exit   "bash-gate: cat /cleanup/... + rnd-integrator → exit 0" 0

# ---------------------------------------------------------------------------
# glob-grep-gate.sh — /cleanup/ barrier
# ---------------------------------------------------------------------------

printf '\n--- glob-grep-gate.sh: /cleanup/ barrier ---\n'

# 6. Glob tool — rnd-verifier is blocked
run_hook "$GLOB_GREP_GATE" \
  '{"tool_name":"Glob","tool_input":{"path":"'"$CLEANUP_PATH"'"},"agent_type":"rnd-verifier"}'
assert_exit   "glob-grep-gate: Glob /cleanup/ + rnd-verifier → exit 2" 2
assert_stderr_contains "glob-grep-gate: Glob /cleanup/ + rnd-verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# 7. Grep tool — rnd-verifier is blocked
run_hook "$GLOB_GREP_GATE" \
  '{"tool_name":"Grep","tool_input":{"path":"'"$CLEANUP_PATH"'","pattern":".*"},"agent_type":"rnd-verifier"}'
assert_exit   "glob-grep-gate: Grep /cleanup/ + rnd-verifier → exit 2" 2
assert_stderr_contains "glob-grep-gate: Grep /cleanup/ + rnd-verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# 8. rnd-integrator is not blocked
run_hook "$GLOB_GREP_GATE" \
  '{"tool_name":"Glob","tool_input":{"path":"'"$CLEANUP_PATH"'"},"agent_type":"rnd-integrator"}'
assert_exit   "glob-grep-gate: Glob /cleanup/ + rnd-integrator → exit 0" 0

# 9. Anti-false-positive: bare word "cleanup" in Grep pattern (no slashes) does NOT trigger barrier
run_hook "$GLOB_GREP_GATE" \
  '{"tool_name":"Grep","tool_input":{"pattern":"cleanup","path":"/Users/someone/project/src/util.ts"},"agent_type":"rnd-verifier"}'
assert_exit   "glob-grep-gate: bare 'cleanup' pattern + verifier → exit 0 (no barrier)" 0

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
