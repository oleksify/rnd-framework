#!/usr/bin/env bash
# tests/assumptions-prereg.test.sh — Smoke tests for the Assumptions/Refuted-by section
# in the pre-registration template and Verifier enforcement instructions.
# Usage: bash tests/assumptions-prereg.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

DECOMP_SKILL="${PLUGIN_ROOT}/skills/rnd-decomposition/SKILL.md"
ORCH_SKILL="${PLUGIN_ROOT}/skills/rnd-orchestration/SKILL.md"
VERIF_SKILL="${PLUGIN_ROOT}/skills/rnd-verification/SKILL.md"
VERIFIER_AGENT="${PLUGIN_ROOT}/agents/rnd-verifier.md"

decomp_content="$(cat "$DECOMP_SKILL")"
orch_content="$(cat "$ORCH_SKILL")"
verif_content="$(cat "$VERIF_SKILL")"
agent_content="$(cat "$VERIFIER_AGENT")"

printf '\n--- rnd-decomposition: Assumptions section in pre-reg template ---\n'

assert_contains "decomposition skill has Assumptions section" \
  "Assumptions:" "$decomp_content"

assert_contains "decomposition skill has Assumption: sub-field" \
  "Assumption:" "$decomp_content"

assert_contains "decomposition skill has Refuted by: sub-field" \
  "Refuted by:" "$decomp_content"

assert_contains "decomposition skill states section is REQUIRED" \
  "REQUIRED" "$decomp_content"

assert_contains "decomposition skill requires - None placeholder when no assumptions" \
  "- None" "$decomp_content"

printf '\n--- rnd-orchestration: Assumptions section in pre-reg template ---\n'

assert_contains "orchestration skill has Assumptions section" \
  "Assumptions:" "$orch_content"

assert_contains "orchestration skill has Assumption: sub-field" \
  "Assumption:" "$orch_content"

assert_contains "orchestration skill has Refuted by: sub-field" \
  "Refuted by:" "$orch_content"

assert_contains "orchestration skill states section is REQUIRED" \
  "REQUIRED" "$orch_content"

assert_contains "orchestration skill requires - None placeholder when no assumptions" \
  "- None" "$orch_content"

printf '\n--- rnd-verification: Assumption Checks sub-section ---\n'

assert_contains "verification skill has Assumption Checks sub-section" \
  "Assumption Checks" "$verif_content"

assert_contains "verification skill instructs check of Refuted by evidence" \
  "Refuted by" "$verif_content"

assert_contains "verification skill specifies PASS to PASS_QUALITY_NEEDS_ITERATION downgrade" \
  "PASS → PASS_QUALITY_NEEDS_ITERATION" "$verif_content"

assert_contains "verification skill specifies PASS_QUALITY_NEEDS_ITERATION to NEEDS_ITERATION downgrade" \
  "PASS_QUALITY_NEEDS_ITERATION → NEEDS_ITERATION" "$verif_content"

assert_contains "verification skill states enforcement is NEEDS_ITERATION not hard FAIL" \
  "NEEDS_ITERATION trigger, not" "$verif_content"

assert_contains "verification skill references rnd-framework:rnd-calibration for gateFired schema" \
  "rnd-framework:rnd-calibration" "$verif_content"

assert_contains "verification skill specifies assumption_unchecked gate name" \
  "assumption_unchecked" "$verif_content"

printf '\n--- rnd-verifier agent: Assumption refutation enforcement rule ---\n'

assert_contains "verifier agent has Assumption Refutation Enforcement section" \
  "Assumption Refutation Enforcement" "$agent_content"

assert_contains "verifier agent specifies gateFired emission" \
  "gateFired" "$agent_content"

assert_contains "verifier agent specifies assumption_unchecked gate name" \
  "assumption_unchecked" "$agent_content"

assert_contains "verifier agent references rnd-framework:rnd-calibration for schema" \
  "rnd-framework:rnd-calibration" "$agent_content"

assert_contains "verifier agent specifies NEEDS_ITERATION not hard FAIL" \
  "NEEDS_ITERATION trigger, not" "$agent_content"

report
