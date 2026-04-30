#!/usr/bin/env bash
# tests/bash-gate-env-prefix-quote.test.sh — Tests for strip_env_prefix unmatched-quote blocking.
# Usage: bash tests/bash-gate-env-prefix-quote.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

HOOK_DIR="${SCRIPT_DIR}/../hooks"

# Extract function definitions from bash-gate.sh (same technique as other tests).
_FUNCS_FILE="$(mktemp)"
awk '
  !past_header && /^source / { past_header=1; next }
  !past_header { next }
  /^# Main$/ { in_main=1 }
  /^# -+$/ && in_main { exit }
  !in_main { print }
' "${HOOK_DIR}/bash-gate.sh" > "$_FUNCS_FILE"

run_strip_env_prefix() {
  local seg="$1"
  bash -c "
    source '${HOOK_DIR}/lib.sh'
    source '$_FUNCS_FILE'
    strip_env_prefix $(printf '%q' "$seg")
  "
}

printf '%s\n' '--- strip_env_prefix unmatched quote detection ---'

# A segment with unmatched double-quote in value must emit blocked: prefix
result="$(run_strip_env_prefix 'FOO="abc def" sed /etc/hosts')"
assert_contains "unmatched double-quote in env value is blocked" "blocked:" "$result"

result="$(run_strip_env_prefix "FOO='abc def' sed /etc/hosts")"
assert_contains "unmatched single-quote in env value is blocked" "blocked:" "$result"

# Normal env prefix (no spaces in value) must still strip and allow downstream check
result="$(run_strip_env_prefix 'FOO=bar sed /etc/hosts')"
[[ "$result" != blocked:* ]] && {
  printf '  PASS  clean env prefix passes through strip_env_prefix\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
} || {
  printf '  FAIL  clean env prefix passes through strip_env_prefix\n'
  printf '        actual: %s\n' "$result"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# No env prefix at all — must pass through unchanged
result="$(run_strip_env_prefix 'sed /etc/hosts')"
assert_eq "no env prefix: segment returned unchanged" "sed /etc/hosts" "$result"

rm -f "$_FUNCS_FILE"
report
