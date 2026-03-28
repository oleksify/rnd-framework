#!/usr/bin/env bash
# Tests for the pure-function refactor of bash-gate.sh.
# Verifies check_segment stdout protocol and split_and_check structured output.
# Usage: bash tests/prefer-tools-sh-refactor.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_DIR="${SCRIPT_DIR}/../hooks"

PASS=0
FAIL=0

pass() { printf 'PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL  %s — %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Source the hook in a subshell to avoid polluting the test environment.
# We redirect stdin so `raw="$(cat)"` in main doesn't block waiting for input.
# We use a wrapper that sources the functions-only portion of the hook.
#
# Strategy: source lib.sh and the hook up to (but not including) main,
# then call the functions directly.
# ---------------------------------------------------------------------------

# Build a small sourcing shim that loads only the function definitions.
# We do this by creating a temporary file that sources lib.sh and defines
# the hook functions, but does NOT execute the main body.
_shim() {
  # Source lib.sh first
  source "${HOOK_DIR}/lib.sh"

  # Source just the function definitions from bash-gate.sh by processing
  # the file with awk to strip the main body (everything after "# Main" section
  # and the top-level raw/command lines).
  # Simpler approach: source the whole file with a dummy stdin and capture
  # function definitions by running in a subshell that exits before main runs.
  #
  # The cleanest approach: use a separate bash invocation that sources the file
  # with empty stdin, so main exits at `if [[ -z "$command" ]]; then exit 0; fi`
  # Then call the functions in that same process via `bash -c "source ...; func"`.
  true
}

# Extract only function definitions from bash-gate.sh.
# Skip lines 1-19 (shebang + comment header + source lib.sh line) and
# stop before the main body (which starts after the "# Main" section header).
# The result is a temporary file we source with lib.sh already pre-loaded,
# giving us check_segment and split_and_check without triggering the main body.
_FUNCS_FILE="$(mktemp)"
awk '
  NR <= 21 { next }
  /^# Main$/ { in_main=1 }
  /^# -+$/ && in_main { exit }
  !in_main { print }
' "${HOOK_DIR}/bash-gate.sh" > "$_FUNCS_FILE"

# Run check_segment via a sourced subshell.
# Usage: run_check_segment "command_string"
# Sets: CS_RESULT (stdout), CS_EXIT (exit code)
run_check_segment() {
  local cmd="$1"
  CS_RESULT=""
  CS_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  bash -c "
    source '${HOOK_DIR}/lib.sh'
    source '$_FUNCS_FILE'
    check_segment $(printf '%q' "$cmd")
  " >"$tmp_out" 2>"$tmp_err" || CS_EXIT=$?
  CS_RESULT="$(cat "$tmp_out")"
  rm -f "$tmp_out" "$tmp_err"
}

# Run split_and_check via a sourced subshell.
# Usage: run_split_and_check "command_string"
# Sets: SAC_RESULT (stdout), SAC_EXIT (exit code)
run_split_and_check() {
  local cmd="$1"
  SAC_RESULT=""
  SAC_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  bash -c "
    source '${HOOK_DIR}/lib.sh'
    source '$_FUNCS_FILE'
    split_and_check $(printf '%q' "$cmd")
  " >"$tmp_out" 2>"$tmp_err" || SAC_EXIT=$?
  SAC_RESULT="$(cat "$tmp_out")"
  rm -f "$tmp_out" "$tmp_err"
}

# ---------------------------------------------------------------------------
# check_segment output protocol tests
# ---------------------------------------------------------------------------

# Criterion: check_segment("sed s/foo/bar/ file") prints string starting with "blocked:"
run_check_segment "sed s/foo/bar/ file"
if [[ "$CS_RESULT" == blocked:* ]]; then
  pass "check_segment: sed prints blocked: prefix on stdout"
else
  fail "check_segment: sed prints blocked: prefix on stdout" "got: '$CS_RESULT'"
fi

# Criterion: check_segment("ls -la") prints "allowed" on stdout
run_check_segment "ls -la"
if [[ "$CS_RESULT" == "allowed" ]]; then
  pass "check_segment: ls -la prints 'allowed' on stdout"
else
  fail "check_segment: ls -la prints 'allowed' on stdout" "got: '$CS_RESULT'"
fi

# Criterion: check_segment("echo hello") prints "echo_safe" on stdout
run_check_segment "echo hello"
if [[ "$CS_RESULT" == "echo_safe" ]]; then
  pass "check_segment: echo hello prints 'echo_safe' on stdout"
else
  fail "check_segment: echo hello prints 'echo_safe' on stdout" "got: '$CS_RESULT'"
fi

# Additional protocol checks
run_check_segment "grep pattern file"
if [[ "$CS_RESULT" == blocked:* ]]; then
  pass "check_segment: grep prints blocked: prefix on stdout"
else
  fail "check_segment: grep prints blocked: prefix on stdout" "got: '$CS_RESULT'"
fi

run_check_segment "cat somefile"
if [[ "$CS_RESULT" == blocked:* ]]; then
  pass "check_segment: cat prints blocked: prefix on stdout"
else
  fail "check_segment: cat prints blocked: prefix on stdout" "got: '$CS_RESULT'"
fi

run_check_segment "find . -name '*.ts'"
if [[ "$CS_RESULT" == blocked:* ]]; then
  pass "check_segment: find prints blocked: prefix on stdout"
else
  fail "check_segment: find prints blocked: prefix on stdout" "got: '$CS_RESULT'"
fi

run_check_segment "printf hello"
if [[ "$CS_RESULT" == "echo_safe" ]]; then
  pass "check_segment: printf without redirect prints 'echo_safe' on stdout"
else
  fail "check_segment: printf without redirect prints 'echo_safe' on stdout" "got: '$CS_RESULT'"
fi

run_check_segment "npm install"
if [[ "$CS_RESULT" == "allowed" ]]; then
  pass "check_segment: npm install prints 'allowed' on stdout"
else
  fail "check_segment: npm install prints 'allowed' on stdout" "got: '$CS_RESULT'"
fi

# Criterion: blocked: reason contains useful text (not empty)
run_check_segment "sed s/a/b/ file"
blocked_reason="${CS_RESULT#blocked:}"
if [[ -n "$blocked_reason" ]]; then
  pass "check_segment: blocked reason is non-empty"
else
  fail "check_segment: blocked reason is non-empty" "got empty reason in: '$CS_RESULT'"
fi

# ---------------------------------------------------------------------------
# check_segment does NOT reference or modify global mutable state
# ---------------------------------------------------------------------------

# After calling check_segment, globals SEGMENT_BLOCKED/BLOCK_REASON/HAS_ECHO
# must not be set. We verify by checking they are not defined in the subshell.
run_check_segment_env() {
  local cmd="$1"
  bash -c "
    source '${HOOK_DIR}/lib.sh'
    source '$_FUNCS_FILE'
    check_segment $(printf '%q' "$cmd") > /dev/null
    # If any of these vars are set, print them
    if [[ -v SEGMENT_BLOCKED ]]; then echo 'SEGMENT_BLOCKED_SET'; fi
    if [[ -v BLOCK_REASON ]];    then echo 'BLOCK_REASON_SET'; fi
    if [[ -v HAS_ECHO ]];        then echo 'HAS_ECHO_SET'; fi
  " 2>/dev/null || true
}

globals_output="$(run_check_segment_env "sed s/a/b/ file")"
if [[ -z "$globals_output" ]]; then
  pass "check_segment: does not set SEGMENT_BLOCKED, BLOCK_REASON, or HAS_ECHO"
else
  fail "check_segment: does not set SEGMENT_BLOCKED, BLOCK_REASON, or HAS_ECHO" "found: $globals_output"
fi

globals_output="$(run_check_segment_env "echo hello")"
if [[ -z "$globals_output" ]]; then
  pass "check_segment (echo_safe): does not set HAS_ECHO global"
else
  fail "check_segment (echo_safe): does not set HAS_ECHO global" "found: $globals_output"
fi

# ---------------------------------------------------------------------------
# split_and_check structured result tests
# ---------------------------------------------------------------------------

# Criterion: split_and_check returns structured result on stdout (not via globals)
run_split_and_check "sed s/foo/bar/ file"
if [[ "$SAC_RESULT" == blocked:* ]]; then
  pass "split_and_check: returns blocked: on stdout for sed"
else
  fail "split_and_check: returns blocked: on stdout for sed" "got: '$SAC_RESULT'"
fi

run_split_and_check "ls -la"
if [[ "$SAC_RESULT" == "allowed" ]]; then
  pass "split_and_check: returns 'allowed' on stdout for ls"
else
  fail "split_and_check: returns 'allowed' on stdout for ls" "got: '$SAC_RESULT'"
fi

run_split_and_check "npm test && echo results"
if [[ "$SAC_RESULT" == "echo_safe" ]]; then
  pass "split_and_check: returns 'echo_safe' for npm && echo"
else
  fail "split_and_check: returns 'echo_safe' for npm && echo" "got: '$SAC_RESULT'"
fi

run_split_and_check "npm install && cat package.json"
if [[ "$SAC_RESULT" == blocked:* ]]; then
  pass "split_and_check: returns blocked: for compound with cat"
else
  fail "split_and_check: returns blocked: for compound with cat" "got: '$SAC_RESULT'"
fi

# ---------------------------------------------------------------------------
# Quality: no global mutable variables in the file
# ---------------------------------------------------------------------------

has_globals=0
for varname in SEGMENT_BLOCKED BLOCK_REASON HAS_ECHO; do
  if grep -q "^${varname}=" "${HOOK_DIR}/bash-gate.sh" 2>/dev/null; then
    fail "no global mutable: ${varname} is declared at module level" "found in file"
    has_globals=1
  fi
done
if [[ "$has_globals" -eq 0 ]]; then
  pass "no global mutable: SEGMENT_BLOCKED, BLOCK_REASON, HAS_ECHO removed"
fi

# ---------------------------------------------------------------------------
# Quality: readonly module-level constants exist
# ---------------------------------------------------------------------------

check_readonly() {
  local varname="$1"
  if grep -q "^readonly ${varname}=" "${HOOK_DIR}/bash-gate.sh" 2>/dev/null; then
    pass "readonly constant: ${varname} declared at module level"
  else
    fail "readonly constant: ${varname} declared at module level" "not found in file"
  fi
}

check_readonly "_CD_AND_PATTERN"
check_readonly "_CD_DSEMI_PATTERN"
check_readonly "_CD_SEMI_PATTERN"
check_readonly "_DOLLAR_PAREN_PATTERN"
check_readonly "_BACKTICK_PATTERN"
check_readonly "_TMP_REDIRECT_PATTERN"
check_readonly "_PROTECTED_BRANCHES"


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

rm -f "$_FUNCS_FILE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
