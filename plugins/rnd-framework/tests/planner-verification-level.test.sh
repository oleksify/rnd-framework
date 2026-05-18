#!/usr/bin/env bash
# tests/planner-verification-level.test.sh — Verification level enum update tests.
# Asserts the new enum is in place, the classifier is integrated, and a docs-only
# fixture produces the "inline" recommendation.
# Usage: bash tests/planner-verification-level.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CLASSIFY="${PLUGIN_ROOT}/lib/criteria-classify.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Schema presence: new enum in rnd-decomposition skill and planner agent
# ---------------------------------------------------------------------------

printf '\n--- planner-verification-level: enum in rnd-decomposition/SKILL.md ---\n'

skill_file="${PLUGIN_ROOT}/skills/rnd-decomposition/SKILL.md"
match_count="$(grep -cE "Verification level: inline \| unit \| system" "$skill_file" || true)"

assert_eq "rnd-decomposition/SKILL.md contains new enum" "1" "$match_count"

printf '\n--- planner-verification-level: enum in agents/rnd-planner.md ---\n'

planner_file="${PLUGIN_ROOT}/agents/rnd-planner.md"
planner_match="$(grep -cE "Verification level: inline \| unit \| system" "$planner_file" || true)"

assert_eq "rnd-planner.md contains new enum" "1" "$planner_match"

# ---------------------------------------------------------------------------
# Old enum absent: no occurrence of the removed "integration" value
# ---------------------------------------------------------------------------

printf '\n--- planner-verification-level: old enum absent ---\n'

old_count="$(grep -rE "Verification level: unit \| integration \| system" \
  "${PLUGIN_ROOT}/agents/" "${PLUGIN_ROOT}/skills/" "${PLUGIN_ROOT}/commands/" 2>/dev/null \
  | grep -cv "^$" || true)"

assert_eq "old 'unit | integration | system' enum not present anywhere" "0" "$old_count"

# ---------------------------------------------------------------------------
# Planner prompt directs use of classifier
# ---------------------------------------------------------------------------

printf '\n--- planner-verification-level: planner prompt references classifier ---\n'

classifier_ref="$(grep -c "criteria-classify" "$planner_file" || true)"

assert_eq "rnd-planner.md references criteria-classify.sh" "1" "$classifier_ref"

# ---------------------------------------------------------------------------
# Override path documented in planner
# ---------------------------------------------------------------------------

printf '\n--- planner-verification-level: override path documented ---\n'

override_ref="$(grep -c "decisions.md" "$planner_file" || true)"

[[ "$override_ref" -ge 1 ]] && override_pass="yes" || override_pass="no"
assert_eq "rnd-planner.md mentions decisions.md for override logging" "yes" "$override_pass"

# ---------------------------------------------------------------------------
# verification_level_assigned emit in rnd-start.md
# ---------------------------------------------------------------------------

printf '\n--- planner-verification-level: verification_level_assigned in rnd-start.md ---\n'

start_file="${PLUGIN_ROOT}/commands/rnd-start.md"
emit_count="$(grep -c "verification_level_assigned" "$start_file" || true)"

[[ "$emit_count" -ge 1 ]] && emit_pass="yes" || emit_pass="no"
assert_eq "rnd-start.md contains verification_level_assigned" "yes" "$emit_pass"

# ---------------------------------------------------------------------------
# Docs-only fixture: classifier returns "inline"
# Simulates the most concrete "Planner would emit inline for docs-only seed" check.
# The planner is instructed to use the classifier output as the default level.
# ---------------------------------------------------------------------------

printf '\n--- planner-verification-level: docs-only fixture yields inline ---\n'

docs_fixture="${TMP_DIR}/docs-only-prereg.md"

cat > "$docs_fixture" << 'PREREG'
Task ID: T99
Intent: Update README to document the new verification level enum.
Approach: Edit README.md to replace old enum with the new one.
Expected outputs:
  - README.md (modified)
Criticality: LOW
Success criteria:

## Correctness

- [ ] grep -E "inline | unit | system" README.md returns ≥1 line.
- [ ] grep -c "integration" README.md returns 0 lines.

## Quality

- [ ] Wording is clear and follows existing doc style.
Verification level: inline
Dependencies: None
Assumptions:
  - None
fulfills: [VAL-DOCS-001]
PREREG

docs_out="$(bash "$CLASSIFY" "$docs_fixture")"
docs_level="$(printf '%s' "$docs_out" | grep -o '"recommended_level":"[a-z]*"' | grep -o '"[a-z]*"$' | tr -d '"')"

assert_eq "docs-only fixture: classifier recommends inline" "inline" "$docs_level"

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

report
