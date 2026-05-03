#!/usr/bin/env bash
# tests/lib-is-barrier-violation.test.sh — Tests for is_barrier_violation in hooks/lib.sh.
# Usage: bash tests/lib-is-barrier-violation.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

LIB="${SCRIPT_DIR}/../hooks/lib.sh"
# shellcheck source=../hooks/lib.sh
source "$LIB"

printf '%s\n' '--- is_barrier_violation ---'

TEXT="path/to/self-assessment.md"

# Lean theorem: proofGate_cannot_access_self_assessment
# proof-gate agent must be blocked from self-assessment paths
if is_barrier_violation "$TEXT" "rnd-proof-gate"; then
  assert_eq "proof-gate blocked from self-assessment (proofGate_cannot_access_self_assessment)" "0" "0"
else
  assert_eq "proof-gate blocked from self-assessment (proofGate_cannot_access_self_assessment)" "0" "1"
fi

# Regression: verifier must still be blocked
if is_barrier_violation "$TEXT" "rnd-verifier"; then
  assert_eq "verifier blocked from self-assessment (regression)" "0" "0"
else
  assert_eq "verifier blocked from self-assessment (regression)" "0" "1"
fi

# Builder must NOT be blocked
if is_barrier_violation "$TEXT" "rnd-builder"; then
  assert_eq "builder NOT blocked from self-assessment" "1" "0"
else
  assert_eq "builder NOT blocked from self-assessment" "1" "1"
fi

# Regression: empty agent_type must be blocked
if is_barrier_violation "$TEXT" ""; then
  assert_eq "empty agent_type blocked from self-assessment (regression)" "0" "0"
else
  assert_eq "empty agent_type blocked from self-assessment (regression)" "0" "1"
fi

report
