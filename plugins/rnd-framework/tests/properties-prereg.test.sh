#!/usr/bin/env bash
# tests/properties-prereg.test.sh — Smoke tests for the Properties subsection
# in the pre-registration template inside both skills.
# Usage: bash tests/properties-prereg.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

DECOMP_SKILL="${PLUGIN_ROOT}/skills/rnd-decomposition/SKILL.md"
ORCH_SKILL="${PLUGIN_ROOT}/skills/rnd-orchestration/SKILL.md"

decomp_content="$(cat "$DECOMP_SKILL")"
orch_content="$(cat "$ORCH_SKILL")"

printf '\n--- rnd-decomposition: Properties subsection in pre-reg template ---\n'

assert_contains "decomposition skill has Properties section" \
  "## Properties" "$decomp_content"

assert_contains "decomposition skill documents markdown bullets shape" \
  "markdown bullets" "$decomp_content"

assert_contains "decomposition skill documents YAML block shape" \
  "YAML block" "$decomp_content"

assert_contains "decomposition skill documents sibling file shape" \
  "sibling file" "$decomp_content"

assert_contains "decomposition skill includes markdown bullets example" \
  "forall" "$decomp_content"

assert_contains "decomposition skill includes YAML block example" \
  "properties:" "$decomp_content"

assert_contains "decomposition skill includes sibling file example" \
  "properties.exs" "$decomp_content"

assert_contains "decomposition skill includes dispatch table" \
  "markdown bullets" "$decomp_content"

printf '\n--- rnd-orchestration: Properties subsection in pre-reg template ---\n'

assert_contains "orchestration skill has Properties section" \
  "## Properties" "$orch_content"

assert_contains "orchestration skill documents markdown bullets shape" \
  "markdown bullets" "$orch_content"

assert_contains "orchestration skill documents YAML block shape" \
  "YAML block" "$orch_content"

assert_contains "orchestration skill documents sibling file shape" \
  "sibling file" "$orch_content"

report
