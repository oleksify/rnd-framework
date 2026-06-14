#!/usr/bin/env bash
# tests/write-gate.test.sh — Tests for hooks/write-gate.sh
set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

ACTIVE_BASE_DIR="${CLAUDE_CONFIG_DIR}/.rnd/test-slug/branches/main"
ACTIVE_SESSION_ID="20260613-160331-abcd"
ACTIVE_RND_DIR="${ACTIVE_BASE_DIR}/sessions/${ACTIVE_SESSION_ID}"

mkdir -p "${CLAUDE_CONFIG_DIR}/.rnd" "${ACTIVE_RND_DIR}/builds"
printf '%s' "${ACTIVE_BASE_DIR}" > "${CLAUDE_CONFIG_DIR}/.rnd/.active-base-dir"
printf '%s' "${ACTIVE_SESSION_ID}" > "${ACTIVE_BASE_DIR}/.current-session"

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
# real artifact-root path → auto-allow
# ---------------------------------------------------------------------------

run_hook "$(jq -nc --arg path "${ACTIVE_RND_DIR}/builds/report.md" '{tool_name:"Write", tool_input:{file_path:$path, content:"test"}}')"
assert_exit "Write active artifact path → exit 0" 0
assert_stdout_contains "Write active artifact path → allow JSON" '"permissionDecision":"allow"'

run_hook "$(jq -nc --arg path "${ACTIVE_RND_DIR}/builds/plan.md" '{tool_name:"Edit", tool_input:{file_path:$path, old_string:"a", new_string:"b"}}')"
assert_exit "Edit active artifact path → exit 0" 0
assert_stdout_contains "Edit active artifact path → allow JSON" '"permissionDecision":"allow"'

# fake .claude*/.rnd/ bypass path → no opinion

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/project/.claude-evil/x/.rnd/secret.txt","content":"test"}}'
assert_exit "Write fake artifact-root bypass path → exit 0" 0
assert_stdout_empty "Write fake artifact-root bypass path → empty stdout (no auto-allow)"

# .rnd/ base-level file under configured root (roadmap.md)

run_hook "$(jq -nc --arg path "${CLAUDE_CONFIG_DIR}/.rnd/test-slug/roadmap.md" '{tool_name:"Write", tool_input:{file_path:$path, content:"test"}}')"
assert_exit "Write configured artifact-root file → exit 0" 0
assert_stdout_contains "Write configured artifact-root file → allow JSON" '"permissionDecision":"allow"'

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
