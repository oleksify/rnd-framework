#!/usr/bin/env bash
# tests/calibration-verification-mode.test.sh — Tests for the verification_mode field
# in the calibration JSONL schema and calibration.sh tolerance of missing optional fields.
# Usage: bash tests/calibration-verification-mode.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CALIB_SKILL="${PLUGIN_ROOT}/skills/rnd-calibration/SKILL.md"
CALIB="${PLUGIN_ROOT}/lib/calibration.sh"

# ---------------------------------------------------------------------------
# Schema documentation assertions
# ---------------------------------------------------------------------------

printf '\n--- calibration schema: verification_mode field ---\n'

skill_content="$(cat "$CALIB_SKILL")"

assert_contains "SKILL.md documents verification_mode field" \
  "verification_mode" "$skill_content"

assert_contains "verification_mode lists 'property' value" \
  "property" "$skill_content"

assert_contains "verification_mode lists 'prose' value" \
  "prose" "$skill_content"

assert_contains "verification_mode lists 'schema' value" \
  "schema" "$skill_content"

assert_contains "verification_mode lists 'skipped' value" \
  "skipped" "$skill_content"

assert_contains "verification_mode names the orchestrator as writer" \
  "orchestrator" "$skill_content"

# ---------------------------------------------------------------------------
# Fixture: calibration.sh tolerance of missing/present verification_mode
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CALIB_DIR="${TMP_DIR}/plugin-data"
mkdir -p "$CALIB_DIR"

CALIB_FILE="${CALIB_DIR}/calibration.jsonl"

# 5 records: one with missing verification_mode, four with each allowed value.
# All have criticality HIGH so window HIGH 5 returns all of them.
printf '%s\n' \
  '{"taskId":"T1","criticality":"HIGH","verdict":"PASS","falseVerdictFlag":null}' \
  '{"taskId":"T2","criticality":"HIGH","verdict":"PASS","falseVerdictFlag":null,"verification_mode":"property"}' \
  '{"taskId":"T3","criticality":"HIGH","verdict":"PASS","falseVerdictFlag":null,"verification_mode":"prose"}' \
  '{"taskId":"T4","criticality":"HIGH","verdict":"PASS","falseVerdictFlag":null,"verification_mode":"schema"}' \
  '{"taskId":"T5","criticality":"HIGH","verdict":"PASS","falseVerdictFlag":null,"verification_mode":"skipped"}' \
  > "$CALIB_FILE"

printf '\n--- calibration.sh window: tolerates missing verification_mode ---\n'

out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" window HIGH 5)"
count="$(printf '%s\n' "$out" | jq -sc 'length')"

assert_eq "window HIGH 5 returns all 5 records" "5" "$count"

# The record without verification_mode should be valid JSON (no error from jq)
first_record="$(printf '%s\n' "$out" | head -1)"
first_task="$(printf '%s' "$first_record" | jq -r '.taskId')"
assert_eq "first record (missing verification_mode) is valid JSON" "T1" "$first_task"

# Confirm the missing field is absent (null via jq // null)
first_mode="$(printf '%s' "$first_record" | jq -r '.verification_mode // "null"')"
assert_eq "missing verification_mode field reads as null" "null" "$first_mode"

printf '\n--- calibration.sh window: records with each allowed value ---\n'

# Check that each value survives the window round-trip
for expected_mode in property prose schema skipped; do
  matched="$(printf '%s\n' "$out" | jq -r --arg m "$expected_mode" 'select(.verification_mode == $m) | .verification_mode')"
  assert_eq "record with verification_mode='$expected_mode' is present" "$expected_mode" "$matched"
done

printf '\n--- calibration.sh window: exits 0 on fixture ---\n'

exit_code=0
CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" window HIGH 5 >/dev/null 2>&1 || exit_code=$?
assert_eq "window HIGH 5 exits 0" "0" "$exit_code"

report
