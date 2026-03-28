#!/usr/bin/env bash
# Tests for hooks/read-gate.sh
# Usage: bash tests/read-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/read-gate.sh"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

assert_stderr_contains() {
  local name="$1"
  local needle="$2"
  if [[ "$HOOK_STDERR" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected stderr to contain '$needle', got: '$HOOK_STDERR'"
  fi
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

# self-assessment with no agent_type → block (exit 2, INFORMATION BARRIER)
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.rnd/builds/T3-self-assessment.md"},"agent_type":""}'
assert_exit   "self-assessment + empty agent_type → exit 2" 2
assert_stderr_contains "self-assessment + empty agent_type → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# self-assessment with verifier agent_type → block
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/builds/T3-self-assessment.md"},"agent_type":"rnd-verifier"}'
assert_exit   "self-assessment + verifier → exit 2" 2
assert_stderr_contains "self-assessment + verifier → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# self-assessment with missing agent_type key (null) → block
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/builds/T3-self-assessment.md"}}'
assert_exit   "self-assessment + null agent_type → exit 2" 2
assert_stderr_contains "self-assessment + null agent_type → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# self-assessment with non-verifier agent_type → exit 0
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/builds/T3-self-assessment.md"},"agent_type":"rnd-builder"}'
assert_exit   "self-assessment + rnd-builder → exit 0" 0
assert_stdout_empty "self-assessment + rnd-builder → empty stdout"

# self-assessment with planner → exit 0
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/builds/T3-self-assessment.md"},"agent_type":"rnd-planner"}'
assert_exit   "self-assessment + rnd-planner → exit 0" 0

# case-insensitive (SELF-ASSESSMENT uppercase) with no agent_type → block
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/builds/T3-SELF-ASSESSMENT.md"},"agent_type":""}'
assert_exit   "SELF-ASSESSMENT uppercase + empty agent_type → exit 2" 2
assert_stderr_contains "SELF-ASSESSMENT uppercase + empty agent_type → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# case-insensitive (Self-Assessment mixed case) with verifier → block
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/builds/T3-Self-Assessment.md"},"agent_type":"rnd-verifier"}'
assert_exit   "Self-Assessment mixed case + verifier → exit 2" 2

# .rnd/ path without self-assessment → allow JSON, exit 0
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude/.rnd/builds/T3-manifest.md"},"agent_type":""}'
assert_exit   ".rnd/ path → exit 0" 0
assert_stdout_contains ".rnd/ path → allow JSON" '"permissionDecision":"allow"'

# .rnd/ path without self-assessment → allow JSON, exit 0
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude-personal/.rnd/design-51e58f69/sessions/20260322/brief.md"},"agent_type":""}'
assert_exit   ".rnd/ path → exit 0" 0
assert_stdout_contains ".rnd/ path → allow JSON" '"permissionDecision":"allow"'

# plugin cache path → allow JSON, exit 0
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude-personal/plugins/cache/oleksify-plugins/rnd-framework/0.12.5/skills/rnd-building/SKILL.md"},"agent_type":""}'
assert_exit   "plugin cache path → exit 0" 0
assert_stdout_contains "plugin cache path → allow JSON" '"permissionDecision":"allow"'

# plugin cache path containing self-assessment → block (self-assessment takes priority)
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude-personal/plugins/cache/oleksify-plugins/rnd-framework/0.12.5/builds/T3-self-assessment.md"},"agent_type":""}'
assert_exit   "plugin cache + self-assessment → exit 2 (barrier first)" 2
assert_stderr_contains "plugin cache + self-assessment → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# path with both .rnd/ and self-assessment → block (self-assessment takes priority)
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude/.rnd/sessions/20260101/builds/T3-self-assessment.md"},"agent_type":""}'
assert_exit   ".rnd/ + self-assessment → exit 2 (barrier first)" 2
assert_stderr_contains ".rnd/ + self-assessment → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# .rnd/ + self-assessment, but non-verifier agent → exit 0 (builder is allowed)
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude/.rnd/sessions/20260101/builds/T3-self-assessment.md"},"agent_type":"rnd-builder"}'
assert_exit   ".rnd/ + self-assessment + rnd-builder → exit 0" 0
assert_stdout_empty ".rnd/ + self-assessment + rnd-builder → empty stdout"

# regular path → exit 0, empty stdout
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/Developer/myproject/src/main.ts"},"agent_type":""}'
assert_exit   "regular path → exit 0" 0
assert_stdout_empty "regular path → empty stdout"

# empty stdin → exit 0, empty stdout
printf '' | "$HOOK" >/dev/null 2>/dev/null
HOOK_EXIT=$?
if [[ "$HOOK_EXIT" -eq 0 ]]; then
  pass "empty stdin → exit 0"
else
  fail "empty stdin → exit 0" "got exit $HOOK_EXIT"
fi

# malformed stdin → exit 0, empty stdout
run_hook 'not json at all'
assert_exit   "malformed stdin → exit 0" 0
assert_stdout_empty "malformed stdin → empty stdout"

# learnings path → allow JSON, exit 0
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude-personal/learnings/INDEX.md"},"agent_type":""}'
assert_exit   "learnings path → exit 0" 0
assert_stdout_contains "learnings path → allow JSON" '"permissionDecision":"allow"'

# learnings path under .claude/ → allow JSON, exit 0
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude/learnings/javascript.md"},"agent_type":""}'
assert_exit   "learnings path under .claude/ → exit 0" 0
assert_stdout_contains "learnings path under .claude/ → allow JSON" '"permissionDecision":"allow"'

# learnings path containing self-assessment → block (self-assessment takes priority)
run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.claude-personal/learnings/self-assessment-notes.md"},"agent_type":""}'
assert_exit   "learnings + self-assessment in path → exit 2 (barrier first)" 2
assert_stderr_contains "learnings + self-assessment in path → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
