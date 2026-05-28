#!/usr/bin/env bash
# tests/outside-view-skill.test.sh — Content tests for skills/outside-view/SKILL.md
# Usage: bash tests/outside-view-skill.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

SKILL="${PLUGIN_ROOT}/skills/outside-view/SKILL.md"
content="$(cat "$SKILL")"

# ---------------------------------------------------------------------------
# Frontmatter (M4.skill.file-exists-with-frontmatter)
# ---------------------------------------------------------------------------
printf '\n--- outside-view skill: frontmatter ---\n'

assert_contains "file exists (readable)" \
  "name: outside-view" "$content"

assert_contains "frontmatter has name: outside-view" \
  "name: outside-view" "$content"

assert_contains "frontmatter has effort: low" \
  "effort: low" "$content"

assert_contains "frontmatter has user-invocable: false" \
  "user-invocable: false" "$content"

assert_contains "frontmatter has description field" \
  "description:" "$content"

# description >= 40 characters
frontmatter_section="$(awk '/^---/{c++;next} c==1' "$SKILL")"
description_line="$(printf '%s' "$frontmatter_section" | grep '^description:')"
description_value="${description_line#description:}"
description_value="${description_value# }"
description_value="${description_value#\"}"
description_value="${description_value%\"}"
desc_length="${#description_value}"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ "$desc_length" -ge 40 ]]; then
  printf '  PASS  description is at least 40 characters (%d chars)\n' "$desc_length"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  description is at least 40 characters (got %d chars: %s)\n' "$desc_length" "$description_value"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

assert_contains "description mentions when mechanism fires" \
  "Phase 1" "$content"

# ---------------------------------------------------------------------------
# Thin-corpus threshold (M4.skill.documents-thin-corpus-threshold)
# ---------------------------------------------------------------------------
printf '\n--- outside-view skill: thin-corpus threshold ---\n'

# n_total < 5 appears exactly once
threshold_count="$(grep -c 'n_total < 5' "$SKILL" || true)"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ "$threshold_count" -eq 1 ]]; then
  printf '  PASS  n_total < 5 appears exactly once\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  n_total < 5 appears exactly once (found %d times)\n' "$threshold_count"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Threshold appears in a sentence (within a line that has more context)
threshold_line="$(grep 'n_total < 5' "$SKILL")"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ "${#threshold_line}" -gt 15 ]]; then
  printf '  PASS  n_total < 5 is in a sentence (not a bare token)\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  n_total < 5 is in a sentence (line too short: %s)\n' "$threshold_line"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

assert_contains "threshold triggers thin-corpus mode" \
  "thin-corpus" "$content"

# N_THIN_CORPUS=5 constant lives in lib/outside-view.sh
# When that script exists, verify values match
INJECTOR="${PLUGIN_ROOT}/lib/outside-view.sh"
if [[ -f "$INJECTOR" ]]; then
  injector_constant_count="$(grep -c '^N_THIN_CORPUS=5$' "$INJECTOR" || true)"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$injector_constant_count" -eq 1 ]]; then
    printf '  PASS  N_THIN_CORPUS=5 declared exactly once in lib/outside-view.sh\n'
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  N_THIN_CORPUS=5 declared exactly once in lib/outside-view.sh (found %d)\n' "$injector_constant_count"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  # Confirm both refer to the same threshold value (5)
  skill_value="$(grep 'n_total < 5' "$SKILL" | grep -o '[0-9]\+' | head -1)"
  script_value="$(grep '^N_THIN_CORPUS=' "$INJECTOR" | grep -o '[0-9]\+' | head -1)"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$skill_value" == "$script_value" ]]; then
    printf '  PASS  skill threshold (%s) matches script constant (%s)\n' "$skill_value" "$script_value"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  skill threshold (%s) differs from script constant (%s)\n' "$skill_value" "$script_value"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  printf '  SKIP  lib/outside-view.sh not yet present — constant cross-check deferred\n'
fi

# ---------------------------------------------------------------------------
# Framing constraint section (M4.skill.documents-framing-constraint)
# ---------------------------------------------------------------------------
printf '\n--- outside-view skill: framing constraint section ---\n'

# Extract the ## Framing constraint section body (skip the header line, stop at next ##)
framing_section="$(awk '/^## Framing constraint$/{found=1;next} found && /^## /{exit} found{print}' "$SKILL")"

assert_contains "framing constraint section present in skill" \
  "## Framing constraint" "$content"

# Case-insensitive match for the three required phrases
framing_lower="$(printf '%s' "$framing_section" | tr '[:upper:]' '[:lower:]')"

assert_contains "framing section contains 'calibration anchor'" \
  "calibration anchor" "$framing_lower"

assert_contains "framing section contains 'not a license'" \
  "not a license" "$framing_lower"

assert_contains "framing section contains 'not a trigger'" \
  "not a trigger" "$framing_lower"

# When lib/outside-view.sh exists, verify rendered block also contains the same three phrases
if [[ -f "$INJECTOR" ]]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  export RND_DIR="$tmpdir"

  rendered_block="$(bash "$INJECTOR" 2>/dev/null || true)"
  rendered_lower="$(printf '%s' "$rendered_block" | tr '[:upper:]' '[:lower:]')"

  assert_contains "rendered block contains '## framing constraint' heading" \
    "## framing constraint" "$rendered_lower"

  assert_contains "rendered block contains 'calibration anchor'" \
    "calibration anchor" "$rendered_lower"

  assert_contains "rendered block contains 'not a license'" \
    "not a license" "$rendered_lower"

  assert_contains "rendered block contains 'not a trigger'" \
    "not a trigger" "$rendered_lower"
fi

report
