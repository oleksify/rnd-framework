#!/usr/bin/env bash
# tests/cross-phrasing-check.test.sh — Tests for lib/cross-phrasing-check.sh
# Usage: bash tests/cross-phrasing-check.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CHECK="${PLUGIN_ROOT}/lib/cross-phrasing-check.sh"
CLASSIFY="${PLUGIN_ROOT}/lib/criteria-classify.sh"

RND_DIR="${RND_DIR:-}"
if [[ -z "$RND_DIR" ]]; then
  RND_DIR="$("${PLUGIN_ROOT}/lib/rnd-dir.sh" 2>/dev/null || printf '')"
fi

if [[ -z "$RND_DIR" ]]; then
  printf 'cross-phrasing-check.test.sh: RND_DIR not available; skipping\n' >&2
  exit 0
fi

TMP_DIR="${RND_DIR}/cross-phrasing-test-fixtures-$$"
mkdir -p "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

write_fixture() {
  local name="$1"
  local content="$2"
  local path="${TMP_DIR}/${name}.md"
  printf '%s\n' "$content" > "$path"
  printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# Verify external dependency: criteria-classify.sh accepts a pre-reg path
# and returns JSON with mechanical_pct, judgment_pct, recommended_level.
# ---------------------------------------------------------------------------

printf '\n--- cross-phrasing: external dependency: criteria-classify.sh contract ---\n'

_dep_fixture="$(write_fixture dep-check "## Correctness

- [ ] exits 0 with valid input.

## Quality
")"
_dep_out="$(bash "$CLASSIFY" "$_dep_fixture")"
assert_contains "criteria-classify returns mechanical_pct" "mechanical_pct" "$_dep_out"
assert_contains "criteria-classify returns recommended_level" "recommended_level" "$_dep_out"

# ---------------------------------------------------------------------------
# Test: --help exits 0 and mentions ADVISORY
# ---------------------------------------------------------------------------

printf '\n--- cross-phrasing: --help ---\n'

help_exit=0
help_out="$(bash "$CHECK" --help 2>&1)" || help_exit=$?

assert_eq "--help exits 0" "0" "$help_exit"
assert_contains "--help mentions ADVISORY" "ADVISORY" "$help_out"
assert_contains "--help mentions usage" "Usage" "$help_out"

# ---------------------------------------------------------------------------
# Fixture (a): all-mechanical — uses jq and bash *.test.sh patterns which are
# mechanical but NOT in the paraphrase substitution rules.
# Paraphrase leaves these lines unchanged → drift_score=0, same level.
# Expected: structurally_equivalent=true, drift_score=0, drifted_items=[]
# ---------------------------------------------------------------------------

printf '\n--- cross-phrasing: fixture (a) all-mechanical — drift_score=0 ---\n'

FIXTURE_A="$(write_fixture fixture-a-all-mechanical "
## Correctness

- [ ] jq parses the output and finds the key.
- [ ] bash tests/foo.test.sh exits 0.
- [ ] jq validates the JSON shape.
- [ ] bash tests/bar.test.sh exits 0 with valid input.

## Quality
")"

out_a="$(RND_DIR="$TMP_DIR" bash "$CHECK" "$FIXTURE_A")"

assert_eq "fixture-a: original_criteria_count=4" \
  "4" \
  "$(printf '%s' "$out_a" | awk -F'"original_criteria_count":' '{print $2}' | cut -d',' -f1)"

assert_eq "fixture-a: structurally_equivalent=true" \
  "true" \
  "$(printf '%s' "$out_a" | awk -F'"structurally_equivalent":' '{print $2}' | cut -d',' -f1)"

assert_eq "fixture-a: drift_score=0" \
  "0" \
  "$(printf '%s' "$out_a" | awk -F'"drift_score":' '{print $2}' | cut -d',' -f1)"

assert_eq "fixture-a: drifted_items=[]" \
  "[]" \
  "$(printf '%s' "$out_a" | awk -F'"drifted_items":' '{print $2}' | tr -d '}')"

# ---------------------------------------------------------------------------
# Fixture (b): all-judgment — criteria with no mechanical patterns.
# Paraphrase substitutions don't apply (no trigger words).
# Classifier returns "system" for both original and paraphrased.
# Expected: structurally_equivalent=true, drift_score=0
# ---------------------------------------------------------------------------

printf '\n--- cross-phrasing: fixture (b) all-judgment — structurally_equivalent=true ---\n'

FIXTURE_B="$(write_fixture fixture-b-all-judgment "
## Correctness

- [ ] The output narrative is clear and concise.
- [ ] Each claim is supported by evidence from the session.
- [ ] The summary accurately reflects the implementation choices.
- [ ] The self-assessment is honest about uncertainties.

## Quality
")"

out_b="$(RND_DIR="$TMP_DIR" bash "$CHECK" "$FIXTURE_B")"

assert_eq "fixture-b: structurally_equivalent=true" \
  "true" \
  "$(printf '%s' "$out_b" | awk -F'"structurally_equivalent":' '{print $2}' | cut -d',' -f1)"

assert_eq "fixture-b: drift_score=0" \
  "0" \
  "$(printf '%s' "$out_b" | awk -F'"drift_score":' '{print $2}' | cut -d',' -f1)"

assert_eq "fixture-b: drifted_items=[]" \
  "[]" \
  "$(printf '%s' "$out_b" | awk -F'"drifted_items":' '{print $2}' | tr -d '}')"

# ---------------------------------------------------------------------------
# Fixture (c): ambiguous/drift edge case — one criterion uses "grep" which
# gets paraphrased to "search for", causing a classification flip
# (mechanical → judgment). The drifted_items list should contain that item.
# Expected: drifted_items has at least one entry containing "grep"
# ---------------------------------------------------------------------------

printf '\n--- cross-phrasing: fixture (c) ambiguous — drifted_items non-empty ---\n'

FIXTURE_C="$(write_fixture fixture-c-ambiguous "
## Correctness

- [ ] grep confirms the pattern is present in output.
- [ ] The response is clear and easy to understand.

## Quality
")"

out_c="$(RND_DIR="$TMP_DIR" bash "$CHECK" "$FIXTURE_C")"

# drifted_items should contain the grep item
assert_contains "fixture-c: drifted_items contains the grep item" \
  "grep" \
  "$out_c"

# drift_score > 0 (at least one item drifted out of 2)
drift_c="$(printf '%s' "$out_c" | awk -F'"drift_score":' '{print $2}' | cut -d',' -f1)"
case "$drift_c" in
  0)
    assert_eq "fixture-c: drift_score > 0" "non-zero" "0"
    ;;
  *)
    assert_eq "fixture-c: drift_score is non-zero" "$drift_c" "$drift_c"
    printf '  (drift_score=%s — pass)\n' "$drift_c"
    ;;
esac

# structurally_equivalent may be true or false depending on level shift —
# but drifted_items must be non-empty, confirmed above

# ---------------------------------------------------------------------------
# Test: output JSON has exactly 5 keys
# ---------------------------------------------------------------------------

printf '\n--- cross-phrasing: JSON shape — exactly 5 keys ---\n'

key_count="$(printf '%s' "$out_a" | grep -o '"[a-zA-Z_]*":' | grep -c .)"
assert_eq "output has exactly 5 keys" "5" "$key_count"

# Verify all 5 required keys are present
assert_contains "key: original_criteria_count"   "original_criteria_count"   "$out_a"
assert_contains "key: paraphrased_criteria_count" "paraphrased_criteria_count" "$out_a"
assert_contains "key: structurally_equivalent"    "structurally_equivalent"    "$out_a"
assert_contains "key: drift_score"               "drift_score"               "$out_a"
assert_contains "key: drifted_items"             "drifted_items"             "$out_a"

# ---------------------------------------------------------------------------
# Test: determinism — identical input produces identical paraphrase output
# ---------------------------------------------------------------------------

printf '\n--- cross-phrasing: determinism ---\n'

out_a_run2="$(RND_DIR="$TMP_DIR" bash "$CHECK" "$FIXTURE_A")"
assert_eq "same input → same output (run 1 vs run 2)" "$out_a" "$out_a_run2"

# ---------------------------------------------------------------------------
# Test: reorder stability — original→paraphrased and paraphrased→original
# both produce same overall classifier level (idempotent structural check)
# ---------------------------------------------------------------------------

printf '\n--- cross-phrasing: idempotent structural check ---\n'

# For fixture-b (all-judgment), both directions should give system level
level_b_orig="$(bash "$CLASSIFY" "$FIXTURE_B" | awk -F'"recommended_level":"' '{if(NF>1) print $2}' | tr -d '"}')"
assert_eq "fixture-b: original level is system" "system" "$level_b_orig"

# Paraphrased version (no trigger words → identical to original after paraphrase)
# Structurally equivalent was already asserted true above

report
