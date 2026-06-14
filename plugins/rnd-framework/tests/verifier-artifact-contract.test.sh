#!/usr/bin/env bash
# tests/verifier-artifact-contract.test.sh — Verifier artifact contract docs stay aligned.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

VERIFY_SKILL="${PLUGIN_ROOT}/skills/rnd-verify/SKILL.md"
VERIFIER_AGENT="${PLUGIN_ROOT}/agents/rnd-verifier.md"

skill_content="$(cat "$VERIFY_SKILL")"
agent_content="$(cat "$VERIFIER_AGENT")"

printf '\n--- verifier prose report contract ---\n'

assert_contains "verify skill names PASS as producing verification prose" \
  'PASS' "$skill_content"

assert_contains "verify skill references verification prose artifact" \
  '`T<id>-verification.md`' "$skill_content"

assert_contains "verify skill names PASS_QUALITY_NEEDS_ITERATION as producing verification prose" \
  'PASS_QUALITY_NEEDS_ITERATION' "$skill_content"

assert_contains "verify skill names NEEDS_ITERATION as producing verification prose" \
  'NEEDS_ITERATION' "$skill_content"

assert_contains "verify skill names FAIL as producing verification prose" \
  'FAIL' "$skill_content"

assert_contains "verify skill groups all verdict classes with verification prose output" \
  'For every verdict class (PASS, PASS_QUALITY_NEEDS_ITERATION, NEEDS_ITERATION, and FAIL), the Verifier writes `T<id>-verification.md`' "$skill_content"

if grep -Fq 'no prose report is produced' "$VERIFY_SKILL"; then
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL  verify skill no longer says PASS skips the prose report\n'
else
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf '  PASS  verify skill no longer says PASS skips the prose report\n'
fi

printf '\n--- pass receipt contract ---\n'

assert_contains "verify skill describes pass receipt as additive acceptance metadata" \
  'additive acceptance metadata' "$skill_content"

assert_contains "verify skill limits pass receipts to accepted passing tasks" \
  'accepted passing tasks' "$skill_content"

assert_contains "verify skill says pass receipt does not replace the prose report" \
  'does not replace `T<id>-verification.md`' "$skill_content"

assert_contains "verifier agent requires prose reports for every task regardless of verdict" \
  'For every task, regardless of verdict, write a `T<id>-verification.md` full prose report.' "$agent_content"

assert_contains "verifier agent says pass quality tasks get both artifacts" \
  'PASS_QUALITY_NEEDS_ITERATION** tasks get both artifacts' "$agent_content"

report
