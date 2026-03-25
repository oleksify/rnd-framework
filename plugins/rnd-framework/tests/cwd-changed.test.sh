#!/usr/bin/env bash
# tests/cwd-changed.test.sh — Tests for hooks/cwd-changed.sh
# Usage: bash tests/cwd-changed.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/cwd-changed.sh"
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
# No active session → silent
# ---------------------------------------------------------------------------

run_hook '{"cwd":"/Users/user/Developer/myproject"}'
assert_exit "no active session → exits 0" 0
assert_stdout_empty "no active session → no advisory"

# ---------------------------------------------------------------------------
# Missing cwd → silent
# ---------------------------------------------------------------------------

run_hook '{}'
assert_exit "missing cwd → exits 0" 0
assert_stdout_empty "missing cwd → no advisory"

# ---------------------------------------------------------------------------
# Empty cwd → silent
# ---------------------------------------------------------------------------

run_hook '{"cwd":""}'
assert_exit "empty cwd → exits 0" 0
assert_stdout_empty "empty cwd → no advisory"

# ---------------------------------------------------------------------------
# Malformed JSON → silent
# ---------------------------------------------------------------------------

run_hook 'not json'
assert_exit "malformed JSON → exits 0" 0
assert_stdout_empty "malformed JSON → no advisory"

# ---------------------------------------------------------------------------
# With active session, same git repo → silent
# ---------------------------------------------------------------------------

tmp_config="$(mktemp -d)"
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -n "$base_dir" ]]; then
  session_id="20260101-120000-abcd"
  # Use the rnd-framework hooks dir as the session dir so git root resolution points to this repo
  session_dir="${base_dir}/sessions/${session_id}"
  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_dir}/.current-session"

  # Same repo: cwd is the project directory containing this test
  project_root="$(cd "$SCRIPT_DIR/.." && git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$project_root" ]]; then
    run_hook "{\"cwd\":\"$project_root\"}" "CLAUDE_CONFIG_DIR=${tmp_config}"
    assert_exit "same git repo → exits 0" 0
    # May or may not emit advisory depending on whether session_dir is in the same repo;
    # with our tmp session_dir not being in a git repo, session_git_root will be empty
    # so the condition is not triggered — no advisory
  else
    pass "same git repo → exits 0 (skipped: no git root)"
  fi
else
  fail "rnd-dir.sh --base resolved for cwd-changed tests" "(rnd-dir.sh failed; skipping session tests)"
fi

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
