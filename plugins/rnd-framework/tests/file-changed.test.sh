#!/usr/bin/env bash
# tests/file-changed.test.sh — Tests for hooks/file-changed.sh
# Usage: bash tests/file-changed.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

ARTIFACT_SESSION_DIR="${CLAUDE_CONFIG_DIR}/.rnd/test-slug/branches/main/sessions/20260325-120000-abcd"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/file-changed.sh"

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

json_for_path() {
  jq -nc --arg path "$1" '{file_path:$path}'
}

# ---------------------------------------------------------------------------
# plan.md in .rnd/ → specific advisory
# ---------------------------------------------------------------------------

run_hook "$(json_for_path "${ARTIFACT_SESSION_DIR}/plan.md")"
assert_exit "plan.md in .rnd/ → exits 0" 0
assert_stdout_contains "plan.md in .rnd/ → specific advisory with Re-read" "Re-read the plan"
assert_stdout_contains "plan.md in .rnd/ → advisory contains file path" "plan.md"

# Valid JSON advisory
if printf '%s' "$HOOK_STDOUT" | jq . > /dev/null 2>&1; then
  pass "plan.md advisory is valid JSON"
else
  fail "plan.md advisory is valid JSON" "got: '$HOOK_STDOUT'"
fi

# ---------------------------------------------------------------------------
# protocol.md in .rnd/ → same plan advisory as plan.md
# ---------------------------------------------------------------------------

run_hook "$(json_for_path "${ARTIFACT_SESSION_DIR}/protocol.md")"
assert_exit "protocol.md in .rnd/ → exits 0" 0
assert_stdout_contains "protocol.md in .rnd/ → specific advisory with Re-read" "Re-read the plan"
assert_stdout_contains "protocol.md in .rnd/ → advisory contains file path" "protocol.md"

# Valid JSON advisory
if printf '%s' "$HOOK_STDOUT" | jq . > /dev/null 2>&1; then
  pass "protocol.md advisory is valid JSON"
else
  fail "protocol.md advisory is valid JSON" "got: '$HOOK_STDOUT'"
fi

# ---------------------------------------------------------------------------
# iteration-log.md in .rnd/ → specific advisory
# ---------------------------------------------------------------------------

run_hook "$(json_for_path "${ARTIFACT_SESSION_DIR}/iteration-log.md")"
assert_exit "iteration-log.md in .rnd/ → exits 0" 0
assert_stdout_contains "iteration-log.md in .rnd/ → specific advisory with Check" "Check for new iteration"
assert_stdout_contains "iteration-log.md in .rnd/ → advisory contains file name" "iteration-log.md"

# ---------------------------------------------------------------------------
# Other .rnd/ file → generic advisory
# ---------------------------------------------------------------------------

run_hook "$(json_for_path "${ARTIFACT_SESSION_DIR}/builds/manifest.md")"
assert_exit "other .rnd/ file → exits 0" 0
assert_stdout_contains "other .rnd/ file → generic advisory" "RND artifact modified externally"
assert_stdout_contains "other .rnd/ file → advisory contains basename" "manifest.md"

# ---------------------------------------------------------------------------
# Non-.rnd/ file → silent (no output)
# ---------------------------------------------------------------------------

run_hook '{"file_path":"/Users/user/Developer/myproject/src/main.ts"}'
assert_exit "non-.rnd/ file → exits 0" 0
assert_stdout_empty "non-.rnd/ file → no advisory"

# ---------------------------------------------------------------------------
# Missing file_path → silent
# ---------------------------------------------------------------------------

run_hook '{}'
assert_exit "missing file_path → exits 0" 0
assert_stdout_empty "missing file_path → no advisory"

# ---------------------------------------------------------------------------
# Empty file_path → silent
# ---------------------------------------------------------------------------

run_hook '{"file_path":""}'
assert_exit "empty file_path → exits 0" 0
assert_stdout_empty "empty file_path → no advisory"

# ---------------------------------------------------------------------------
# Malformed JSON → silent
# ---------------------------------------------------------------------------

run_hook 'not json'
assert_exit "malformed JSON → exits 0" 0
assert_stdout_empty "malformed JSON → no advisory"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
