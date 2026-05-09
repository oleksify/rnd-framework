#!/usr/bin/env bash
# tests/test-helpers.sh — Test helpers for bash hook testing.
# Source from any test script: source "$(dirname "$0")/test-helpers.sh"

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Run a hook script with stdin JSON, capture stdout, stderr, and exit code.
# Sets HOOK_STDOUT, HOOK_STDERR, HOOK_EXIT in the caller's scope.
run_hook() {
  local hook="$1"
  local stdin_json="${2:-}"

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  printf '%s' "$stdin_json" | "$hook" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"

  rm -f "$stdout_file" "$stderr_file"
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    printf '  PASS  %s\n' "$desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s\n' "$desc"
    printf '        expected: %s\n' "$expected"
    printf '        actual:   %s\n' "$actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$haystack" == *"$needle"* ]]; then
    printf '  PASS  %s\n' "$desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s\n' "$desc"
    printf '        expected to contain: %s\n' "$needle"
    printf '        actual: %s\n' "$haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_exit_code() {
  local desc="$1" expected="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then
    printf '  PASS  %s\n' "$desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s (exit %d, expected %d)\n' "$desc" "$HOOK_EXIT" "$expected"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

report() {
  printf '\n  %d pass, %d fail (%d total)\n' "$TESTS_PASSED" "$TESTS_FAILED" "$TESTS_TOTAL"
  [[ $TESTS_FAILED -eq 0 ]]
}
