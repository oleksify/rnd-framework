#!/usr/bin/env bash
# tests/bash-gate-echo-redirect.test.sh — Tests for check_echo_redirect stderr passthrough.
# Usage: bash tests/bash-gate-echo-redirect.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

HOOK_DIR="${SCRIPT_DIR}/../hooks"

# Extract only function definitions from bash-gate.sh (same technique as prefer-tools-sh-refactor.test.sh).
_FUNCS_FILE="$(mktemp)"
awk '
  !past_header && /^source / { past_header=1; next }
  !past_header { next }
  /^# Main$/ { in_main=1 }
  /^# -+$/ && in_main { exit }
  !in_main { print }
' "${HOOK_DIR}/bash-gate.sh" > "$_FUNCS_FILE"

# Run check_echo_redirect in a subshell so the main hook body is never executed.
run_check_echo_redirect() {
  local cmd="$1"
  bash -c "
    source '${HOOK_DIR}/lib.sh'
    source '$_FUNCS_FILE'
    check_echo_redirect $(printf '%q' "$cmd")
  "
}

printf '%s\n' '--- check_echo_redirect ---'

result="$(run_check_echo_redirect 'echo foo 2>&1')"
assert_eq "echo with 2>&1 stderr redirect is allowed" "allow" "$result"

result="$(run_check_echo_redirect 'echo foo 2>/dev/null')"
assert_eq "echo with 2>/dev/null stderr redirect is allowed" "allow" "$result"

result="$(run_check_echo_redirect 'echo foo > /some/file')"
assert_eq "echo with stdout-to-file redirect is blocked" "block" "$result"

rm -f "$_FUNCS_FILE"
report
