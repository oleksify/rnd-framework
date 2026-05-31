#!/usr/bin/env bash
# tests/post-tool-use.test.sh — Tests for hooks/post-tool-use.sh
# Usage: bash tests/post-tool-use.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/post-dispatch.sh"

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

# ---------------------------------------------------------------------------
# PostToolUse hooks always exit 0 (they must never block)
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test.ts"}}'
assert_exit "Write event → exits 0" 0
assert_stdout_empty "Write event → no stdout (PostToolUse never emits blocking output)"

run_hook '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.ts"}}'
assert_exit "Edit event → exits 0" 0
assert_stdout_empty "Edit event → no stdout"

# ---------------------------------------------------------------------------
# Resilient to malformed / missing inputs
# ---------------------------------------------------------------------------

run_hook '{}'
assert_exit "empty JSON → exits 0" 0

run_hook 'not json'
assert_exit "malformed stdin → exits 0" 0

printf '' | "$HOOK" >/dev/null 2>/dev/null
HOOK_EXIT=$?
if [[ "$HOOK_EXIT" -eq 0 ]]; then pass "empty stdin → exits 0"; else fail "empty stdin → exits 0" "got $HOOK_EXIT"; fi

run_hook '{"tool_name":"Write","tool_input":{}}'
assert_exit "Write with no file_path → exits 0 (short-circuits)" 0
assert_stdout_empty "Write with no file_path → no stdout"

# ---------------------------------------------------------------------------
# Writes audit.jsonl to the active session directory when one exists.
# Build a minimal session structure that rnd-dir.sh can discover.
# ---------------------------------------------------------------------------

# The hook calls active_session_dir → resolve_rnd_dir → rnd-dir.sh
# rnd-dir.sh derives CONFIG_DIR from CLAUDE_CONFIG_DIR.
# The project slug is derived from git rev-parse (or pwd) of the CWD when the
# hook runs. We can control CONFIG_DIR but not the slug, so we use rnd-dir.sh
# itself to compute the correct base path for this directory.

tmp_config="$(mktemp -d)"
# Use rnd-dir.sh to compute the proper base dir with our fake config dir
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" "${SCRIPT_DIR}/../lib/rnd-dir.sh" --base 2>/dev/null || true)"
if [[ -n "$base_dir" ]]; then
  session_id="20260101-120000-abcd"
  session_dir="${base_dir}/sessions/${session_id}"
  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_dir}/.current-session"

  # Run the hook with our fake config dir
  HOOK_STDOUT="" HOOK_STDERR="" HOOK_EXIT=0
  tmp_out="$(mktemp)" tmp_err="$(mktemp)"
  printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/project/src/main.ts"}}' \
    | CLAUDE_CONFIG_DIR="$tmp_config" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")" HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"

  assert_exit "Write with active session → exits 0" 0

  if [[ -f "${session_dir}/audit.jsonl" ]]; then
    pass "audit.jsonl is created in session directory"
    audit_line="$(head -1 "${session_dir}/audit.jsonl")"
    if printf '%s' "$audit_line" | jq . > /dev/null 2>&1; then
      pass "audit.jsonl entry is valid JSON"
    else
      fail "audit.jsonl entry is valid JSON" "got: '$audit_line'"
    fi
    if [[ "$audit_line" == *"/project/src/main.ts"* ]]; then
      pass "audit.jsonl entry contains the file path"
    else
      fail "audit.jsonl entry contains the file path" "got: '$audit_line'"
    fi
    if [[ "$audit_line" == *'"Write"'* ]]; then
      pass "audit.jsonl entry contains the tool name"
    else
      fail "audit.jsonl entry contains the tool name" "got: '$audit_line'"
    fi
    if [[ "$audit_line" == *'"ts"'* ]]; then
      pass "audit.jsonl entry contains a timestamp field"
    else
      fail "audit.jsonl entry contains a timestamp field" "got: '$audit_line'"
    fi
  else
    fail "audit.jsonl is created in session directory" "not found at ${session_dir}/audit.jsonl"
    fail "audit.jsonl entry is valid JSON" "no file to check"
    fail "audit.jsonl entry contains the file path" "no file to check"
    fail "audit.jsonl entry contains the tool name" "no file to check"
    fail "audit.jsonl entry contains a timestamp field" "no file to check"
  fi
else
  fail "rnd-dir.sh --base returned non-empty path" "(rnd-dir.sh failed; skipping audit write tests)"
  fail "audit.jsonl is created in session directory" "(skipped)"
  fail "audit.jsonl entry is valid JSON" "(skipped)"
  fail "audit.jsonl entry contains the file path" "(skipped)"
  fail "audit.jsonl entry contains the tool name" "(skipped)"
  fail "audit.jsonl entry contains a timestamp field" "(skipped)"
fi

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
