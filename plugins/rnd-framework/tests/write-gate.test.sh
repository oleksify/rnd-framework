#!/usr/bin/env bash
# tests/write-gate.test.sh — Tests for hooks/write-gate.sh
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
  HOOK_STDOUT="$(< "$tmp_out")"
  HOOK_STDERR="$(< "$tmp_err")"
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

# ---------------------------------------------------------------------------
# .rnd/ path → auto-allow
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/Users/alice/.claude-personal/.rnd/slug/sessions/123/brainstorm.md","content":"test"}}'
assert_exit "Write .rnd/ path → exit 0" 0
assert_stdout_contains "Write .rnd/ path → allow JSON" '"permissionDecision":"allow"'

run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/Users/alice/.claude/.rnd/slug/sessions/123/plan.md","old_string":"a","new_string":"b"}}'
assert_exit "Edit .rnd/ path → exit 0" 0
assert_stdout_contains "Edit .rnd/ path → allow JSON" '"permissionDecision":"allow"'

# .rnd/ base-level file (roadmap.md)

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/Users/alice/.claude-personal/.rnd/slug/roadmap.md","content":"test"}}'
assert_exit "Write base-level .rnd/ path → exit 0" 0
assert_stdout_contains "Write base-level .rnd/ path → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# regular path → no opinion
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/Users/alice/project/src/main.ts","content":"test"}}'
assert_exit "regular path → exit 0" 0
assert_stdout_empty "regular path → empty stdout (no opinion)"

# no file_path → no opinion

run_hook '{"tool_name":"Write","tool_input":{"content":"test"}}'
assert_exit "no file_path → exit 0" 0
assert_stdout_empty "no file_path → empty stdout (no opinion)"

# .rnd without .claude prefix → no opinion

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/.rnd/sessions/123/plan.md","content":"test"}}'
assert_exit ".rnd without .claude → exit 0" 0
assert_stdout_empty ".rnd without .claude → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

run_hook "not json"
assert_exit "malformed → exit 0" 0
assert_stdout_empty "malformed → empty stdout"

run_hook ""
assert_exit "empty → exit 0" 0
assert_stdout_empty "empty → empty stdout"

# plugin cache path → no opinion (only artifact paths auto-allowed)

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/Users/alice/.claude/plugins/cache/rnd-framework/settings.json","content":"test"}}'
assert_exit "plugin cache path → exit 0" 0
assert_stdout_empty "plugin cache path → empty stdout (no opinion)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
