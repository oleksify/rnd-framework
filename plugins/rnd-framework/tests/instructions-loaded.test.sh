#!/usr/bin/env bash
# tests/instructions-loaded.test.sh — Tests for hooks/instructions-loaded.sh
# Usage: bash tests/instructions-loaded.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/instructions-loaded.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# outputs advisory JSON and exits 0
# ---------------------------------------------------------------------------
printf '%s\n' '--- instructions-loaded ---'

run_hook "$HOOK" ""

assert_exit_code "instructions-loaded exits 0" 0

# Output must be valid JSON
if printf '%s' "$HOOK_STDOUT" | jq . > /dev/null 2>&1; then
  assert_eq "instructions-loaded outputs valid JSON" "0" "0"
else
  assert_eq "instructions-loaded outputs valid JSON" "0" "1"
fi

# Output must be an advisory (contains additionalContext)
assert_contains "instructions-loaded output contains additionalContext" '"additionalContext"' "$HOOK_STDOUT"

# Advisory text should mention CLAUDE.md
ctx="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
assert_contains "instructions-loaded advisory mentions CLAUDE.md" "CLAUDE.md" "$ctx"

# Advisory text should not be empty
if [[ -n "$ctx" ]]; then
  assert_eq "instructions-loaded advisory context is non-empty" "0" "0"
else
  assert_eq "instructions-loaded advisory context is non-empty" "0" "1"
fi

report
