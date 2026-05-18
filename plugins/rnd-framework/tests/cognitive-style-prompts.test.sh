#!/usr/bin/env bash
# Tests for cognitive-style prompt sections in agent files.
# Usage: bash tests/cognitive-style-prompts.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./test-helpers.sh
source "$_SCRIPT_DIR/test-helpers.sh"

_AGENTS_DIR="$_SCRIPT_DIR/../agents"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_section_exists() {
  local agent_file="$1"
  local agent_name="$2"
  local has_section
  has_section="$(grep -c "^## Cognitive Style" "$agent_file" || true)"
  assert_eq "$agent_name has Cognitive Style section" "1" "$has_section"
}

assert_section_min_lines() {
  local agent_file="$1"
  local agent_name="$2"
  local min_lines="${3:-10}"
  local line_count
  line_count="$(awk '/^## Cognitive Style/{flag=1; next} flag && /^## /{exit} flag{count++} END{print count+0}' "$agent_file")"

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$line_count" -ge "$min_lines" ]]; then
    printf '  PASS  %s section has %d lines (≥%d)\n' "$agent_name" "$line_count" "$min_lines"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s section has %d lines (need ≥%d)\n' "$agent_name" "$line_count" "$min_lines"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_position_comment() {
  local agent_file="$1"
  local agent_name="$2"
  local has_comment
  has_comment="$(grep -c "Cognitive Style additions inject at system-prompt position" "$agent_file" || true)"

  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$has_comment" -ge 1 ]]; then
    printf '  PASS  %s has position-rule comment\n' "$agent_name"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s missing position-rule comment\n' "$agent_name"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# reality-auditor checks
# ---------------------------------------------------------------------------

printf '%s\n' '--- cognitive-style-prompts: reality-auditor ---'

assert_section_exists    "$_AGENTS_DIR/rnd-reality-auditor.md" "rnd-reality-auditor"
assert_section_min_lines "$_AGENTS_DIR/rnd-reality-auditor.md" "rnd-reality-auditor" 10
assert_position_comment  "$_AGENTS_DIR/rnd-reality-auditor.md" "rnd-reality-auditor"

# ---------------------------------------------------------------------------
# verifier checks
# ---------------------------------------------------------------------------

printf '%s\n' '--- cognitive-style-prompts: verifier ---'

assert_section_exists    "$_AGENTS_DIR/rnd-verifier.md" "rnd-verifier"
assert_section_min_lines "$_AGENTS_DIR/rnd-verifier.md" "rnd-verifier" 10
assert_position_comment  "$_AGENTS_DIR/rnd-verifier.md" "rnd-verifier"

# ---------------------------------------------------------------------------
# cleanup checks
# ---------------------------------------------------------------------------

printf '%s\n' '--- cognitive-style-prompts: cleanup ---'

assert_section_exists    "$_AGENTS_DIR/rnd-cleanup.md" "rnd-cleanup"
assert_section_min_lines "$_AGENTS_DIR/rnd-cleanup.md" "rnd-cleanup" 10
assert_position_comment  "$_AGENTS_DIR/rnd-cleanup.md" "rnd-cleanup"

# ---------------------------------------------------------------------------
# drift-detector checks
# ---------------------------------------------------------------------------

printf '%s\n' '--- cognitive-style-prompts: drift-detector ---'

assert_section_exists    "$_AGENTS_DIR/rnd-drift-detector.md" "rnd-drift-detector"
assert_section_min_lines "$_AGENTS_DIR/rnd-drift-detector.md" "rnd-drift-detector" 10
assert_position_comment  "$_AGENTS_DIR/rnd-drift-detector.md" "rnd-drift-detector"

# ---------------------------------------------------------------------------
report
