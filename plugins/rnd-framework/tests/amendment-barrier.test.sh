#!/usr/bin/env bash
# Tests for amendment log barrier enforcement via hooks/read-gate.sh,
# hooks/glob-grep-gate.sh, and hooks/bash-gate.sh.
# Asserts that T<id>-amendments.md paths under /briefs/ are blocked for
# verifier and proof-gate agents, and allowed for builder and orchestrator.
# Usage: bash tests/amendment-barrier.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READ_GATE="${SCRIPT_DIR}/../hooks/read-gate.sh"
GLOB_GREP_GATE="${SCRIPT_DIR}/../hooks/glob-grep-gate.sh"
BASH_GATE="${SCRIPT_DIR}/../hooks/bash-gate.sh"

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

assert_stdout_empty() {
  local name="$1"

  if [[ -z "$HOOK_STDOUT" ]]; then
    pass "$name"
  else
    fail "$name" "expected empty stdout, got: '$HOOK_STDOUT'"
  fi
}

# ---------------------------------------------------------------------------
# Read Gate Barrier
# ---------------------------------------------------------------------------

printf '\n--- Read Gate Barrier ---\n'

# /briefs/T3-amendments.md + rnd-verifier → block (exit 2, INFORMATION BARRIER)
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T3-amendments.md"},"agent_type":"rnd-verifier"}'
assert_exit   "/briefs/T3-amendments.md + rnd-verifier → exit 2" 2
assert_stderr_contains "/briefs/T3-amendments.md + rnd-verifier → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# /briefs/T3-amendments.md + rnd-proof-gate → block (exit 2)
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T3-amendments.md"},"agent_type":"rnd-proof-gate"}'
assert_exit   "/briefs/T3-amendments.md + rnd-proof-gate → exit 2" 2
assert_stderr_contains "/briefs/T3-amendments.md + rnd-proof-gate → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# /briefs/T3-amendments.md + empty agent_type → block (exit 2)
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T3-amendments.md"},"agent_type":""}'
assert_exit   "/briefs/T3-amendments.md + empty agent_type → exit 2" 2
assert_stderr_contains "/briefs/T3-amendments.md + empty agent_type → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# /briefs/T3-amendments.md + rnd-builder → allow (exit 0, builder writes the log)
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T3-amendments.md"},"agent_type":"rnd-builder"}'
assert_exit   "/briefs/T3-amendments.md + rnd-builder → exit 0" 0
assert_stdout_empty "/briefs/T3-amendments.md + rnd-builder → empty stdout (not auto-allowed)"

# /briefs/T3-amendments.md + rnd-planner → allow (exit 0)
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T3-amendments.md"},"agent_type":"rnd-planner"}'
assert_exit   "/briefs/T3-amendments.md + rnd-planner → exit 0" 0
assert_stdout_empty "/briefs/T3-amendments.md + rnd-planner → empty stdout (not auto-allowed)"

# /briefs/T3-amendments.md + rnd-amendment-arbiter → allow (exit 0, arbiter writes the log)
run_hook "$READ_GATE" \
  '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T3-amendments.md"},"agent_type":"rnd-amendment-arbiter"}'
assert_exit   "/briefs/T3-amendments.md + rnd-amendment-arbiter → exit 0" 0
assert_stdout_empty "/briefs/T3-amendments.md + rnd-amendment-arbiter → empty stdout (not auto-allowed)"

# ---------------------------------------------------------------------------
# Glob/Grep Gate Barrier
# ---------------------------------------------------------------------------

printf '\n--- Glob/Grep Gate Barrier ---\n'

# pattern containing "T3-amendments" + rnd-verifier → block (exit 2)
run_hook "$GLOB_GREP_GATE" \
  '{"tool_name":"Grep","tool_input":{"path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/","pattern":"T3-amendments"},"agent_type":"rnd-verifier"}'
assert_exit   "Grep pattern T3-amendments + rnd-verifier → exit 2" 2
assert_stderr_contains "Grep pattern T3-amendments + rnd-verifier → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# path containing "/briefs/T3-amendments.md" + rnd-verifier → block (exit 2)
run_hook "$GLOB_GREP_GATE" \
  '{"tool_name":"Grep","tool_input":{"path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T3-amendments.md","pattern":"AMEND"},"agent_type":"rnd-verifier"}'
assert_exit   "Grep path /briefs/T3-amendments.md + rnd-verifier → exit 2" 2
assert_stderr_contains "Grep path /briefs/T3-amendments.md + rnd-verifier → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# ---------------------------------------------------------------------------
# Bash Gate Barrier
# ---------------------------------------------------------------------------

printf '\n--- Bash Gate Barrier ---\n'

# command containing "/briefs/T3-amendments.md" + rnd-verifier → block (exit 2)
run_hook "$BASH_GATE" \
  '{"tool_name":"Bash","tool_input":{"command":"cat /home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T3-amendments.md"},"agent_type":"rnd-verifier"}'
assert_exit   "Bash /briefs/T3-amendments.md + rnd-verifier → exit 2" 2
assert_stderr_contains "Bash /briefs/T3-amendments.md + rnd-verifier → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
