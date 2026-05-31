#!/usr/bin/env bash
# tests/task-created.test.sh — Tests for hooks/task-created.sh
# Usage: bash tests/task-created.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/task-created.sh"

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
# Script is executable
# ---------------------------------------------------------------------------

if [[ -x "$HOOK" ]]; then pass "script is executable"; else fail "script is executable" "not executable: $HOOK"; fi

# ---------------------------------------------------------------------------
# Always exits 0 (must never block pipeline)
# ---------------------------------------------------------------------------

run_hook '{"task_id":"T1","task_description":"implement feature"}'
assert_exit "task event → exits 0" 0
assert_stdout_empty "task event → no stdout"

run_hook '{}'
assert_exit "empty JSON → exits 0" 0

run_hook 'not json'
assert_exit "malformed stdin → exits 0" 0

printf '' | "$HOOK" >/dev/null 2>/dev/null
HOOK_EXIT=$?
if [[ "$HOOK_EXIT" -eq 0 ]]; then pass "empty stdin → exits 0"; else fail "empty stdin → exits 0" "got $HOOK_EXIT"; fi

# ---------------------------------------------------------------------------
# Writes audit.jsonl to the active session directory when one exists.
# ---------------------------------------------------------------------------

tmp_config="$(mktemp -d)"
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" "${SCRIPT_DIR}/../lib/rnd-dir.sh" --base 2>/dev/null || true)"
if [[ -n "$base_dir" ]]; then
  session_id="20260101-120000-abcd"
  session_dir="${base_dir}/sessions/${session_id}"
  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_dir}/.current-session"

  HOOK_STDOUT="" HOOK_STDERR="" HOOK_EXIT=0
  tmp_out="$(mktemp)" tmp_err="$(mktemp)"
  printf '%s' '{"task_id":"T7","task_description":"build login page"}' \
    | CLAUDE_CONFIG_DIR="$tmp_config" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")" HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"

  assert_exit "task event with active session → exits 0" 0

  if [[ -f "${session_dir}/audit.jsonl" ]]; then
    pass "audit.jsonl is created in session directory"
    audit_line="$(head -1 "${session_dir}/audit.jsonl")"
    if printf '%s' "$audit_line" | jq . > /dev/null 2>&1; then
      pass "audit.jsonl entry is valid JSON"
    else
      fail "audit.jsonl entry is valid JSON" "got: '$audit_line'"
    fi
    if [[ "$audit_line" == *'"task_created"'* ]]; then
      pass "audit.jsonl entry contains event=task_created"
    else
      fail "audit.jsonl entry contains event=task_created" "got: '$audit_line'"
    fi
    if [[ "$audit_line" == *'"T7"'* ]]; then
      pass "audit.jsonl entry contains task_id"
    else
      fail "audit.jsonl entry contains task_id" "got: '$audit_line'"
    fi
    if [[ "$audit_line" == *'"build login page"'* ]]; then
      pass "audit.jsonl entry contains task_description"
    else
      fail "audit.jsonl entry contains task_description" "got: '$audit_line'"
    fi
    if [[ "$audit_line" == *'"ts"'* ]]; then
      pass "audit.jsonl entry contains a timestamp field"
    else
      fail "audit.jsonl entry contains a timestamp field" "got: '$audit_line'"
    fi
  else
    for msg in "audit.jsonl is created in session directory" \
               "audit.jsonl entry is valid JSON" \
               "audit.jsonl entry contains event=task_created" \
               "audit.jsonl entry contains task_id" \
               "audit.jsonl entry contains task_description" \
               "audit.jsonl entry contains a timestamp field"; do
      fail "$msg" "no file at ${session_dir}/audit.jsonl"
    done
  fi
else
  for msg in "rnd-dir.sh --base returned non-empty path" \
             "audit.jsonl is created in session directory" \
             "audit.jsonl entry is valid JSON" \
             "audit.jsonl entry contains event=task_created" \
             "audit.jsonl entry contains task_id" \
             "audit.jsonl entry contains task_description" \
             "audit.jsonl entry contains a timestamp field"; do
    fail "$msg" "(rnd-dir.sh failed; skipping audit write tests)"
  done
fi

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# No write to audit.jsonl when no active session
# ---------------------------------------------------------------------------

tmp_config2="$(mktemp -d)"
base_dir2="$(CLAUDE_CONFIG_DIR="$tmp_config2" "${SCRIPT_DIR}/../lib/rnd-dir.sh" --base 2>/dev/null || true)"
if [[ -n "$base_dir2" ]]; then
  # No .current-session file → no active session
  HOOK_EXIT=0
  printf '%s' '{"task_id":"T1","task_description":"test"}' \
    | CLAUDE_CONFIG_DIR="$tmp_config2" "$HOOK" >/dev/null 2>/dev/null || HOOK_EXIT=$?
  if [[ "$HOOK_EXIT" -eq 0 ]]; then
    pass "no active session → exits 0"
  else
    fail "no active session → exits 0" "got $HOOK_EXIT"
  fi
  if ! find "$base_dir2" -name "audit.jsonl" -type f 2>/dev/null | grep -q .; then
    pass "no active session → no audit.jsonl written"
  else
    fail "no active session → no audit.jsonl written" "file was created unexpectedly"
  fi
fi

rm -rf "$tmp_config2"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
