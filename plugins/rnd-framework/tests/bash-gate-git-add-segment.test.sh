#!/usr/bin/env bash
# tests/bash-gate-git-add-segment.test.sh — Tests for per-segment git-add .rnd/ blocker.
# Verifies that the blocker fires only when `git add` is the command of the segment being
# evaluated, not when .rnd/ happens to appear in a later, unrelated segment.
# Usage: bash tests/bash-gate-git-add-segment.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

BASH_GATE="${SCRIPT_DIR}/../hooks/bash-gate.sh"

_make_json() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"agent_type":"rnd-builder"}' \
    "$(printf '%s' "$cmd" | jq -Rr @json | tr -d '"')"
}

printf '\n--- bash-gate: git-add per-segment blocker ---\n'

# Case A: compound command — git add is benign, .rnd/ appears in a later segment (ls)
# The blocker must NOT fire because git add's argument is not a .rnd/ path.
run_hook "$BASH_GATE" \
  "$(_make_json 'git add foo.txt; ls ~/.claude/.rnd/file')"
assert_exit_code "Case A: compound git-add benign; rnd path in later segment is allowed" 0

# Case B: echo with git add mention — echo is the command, not git add
# The blocker must NOT fire because git add is not the segment command.
run_hook "$BASH_GATE" \
  "$(_make_json 'echo see docs: git add ~/.rnd/foo example')"
assert_exit_code "Case B: echo with git add mention is allowed" 0

# Case C: direct git add of a .rnd/ path — must be blocked (true positive preserved)
run_hook "$BASH_GATE" \
  "$(_make_json 'git add ~/.claude/.rnd/file')"
assert_exit_code "Case C: direct git add .rnd/ path is blocked" 2

report
