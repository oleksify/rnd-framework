#!/usr/bin/env bash
# tests/criteria-classify.test.sh — Tests for lib/criteria-classify.sh
# Usage: bash tests/criteria-classify.test.sh
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
# Helpers
# ---------------------------------------------------------------------------

write_prereg() {
  local name="$1"
  local content="$2"
  local path="${TMP_DIR}/${name}.md"
  printf '%s\n' "$content" > "$path"
  printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# Fixture 1: all-mechanical — 5 items, all match mechanical patterns.
# Expected: mechanical_pct=100, judgment_pct=0, recommended_level=inline
# ---------------------------------------------------------------------------

PREREG_ALL_MECHANICAL="$(write_prereg fixture-all-mechanical "
## Correctness

- [ ] grep output shows expected pattern in results.
- [ ] jq parses the manifest and finds the key.
- [ ] exit code is 0 when run with valid input.
- [ ] file exists at the declared path.
- [ ] wc -l reports at least 10 lines in the output.

## Quality
")"

# ---------------------------------------------------------------------------
# Fixture 2: mostly-mechanical — 4 mechanical, 1 judgment (80%).
# Expected: mechanical_pct=80, judgment_pct=20, recommended_level=inline
# ---------------------------------------------------------------------------

PREREG_MOSTLY_MECHANICAL="$(write_prereg fixture-mostly-mechanical "
## Correctness

- [ ] exits 0 when invoked with valid args.
- [ ] find locates the config file under the expected path.
- [ ] returns ≥ 3 results for the default query.
- [ ] jq selects the correct field from the JSON response.
- [ ] The output reads well and is easy to understand.

## Quality
")"

# ---------------------------------------------------------------------------
# Fixture 3: mixed — 2 mechanical, 3 judgment (40%).
# Expected: mechanical_pct=40, judgment_pct=60, recommended_level=unit
# ---------------------------------------------------------------------------

PREREG_MIXED="$(write_prereg fixture-mixed "
## Correctness

- [ ] grep confirms the pattern is present in the file.
- [ ] exit code is non-zero when the required arg is missing.
- [ ] The error message is clear and actionable.
- [ ] Behavior is consistent across repeated invocations.
- [ ] The implementation is simple enough to reason about.

## Quality
")"

# ---------------------------------------------------------------------------
# Fixture 4: mostly-judgment — 1 mechanical, 4 judgment (20%).
# Expected: mechanical_pct=20, judgment_pct=80, recommended_level=system
# ---------------------------------------------------------------------------

PREREG_MOSTLY_JUDGMENT="$(write_prereg fixture-mostly-judgment "
## Correctness

- [ ] The agent produces a coherent and accurate response.
- [ ] The plan decomposes the problem into testable sub-tasks.
- [ ] Output is easy for a reader to follow.
- [ ] wc -l confirms the report is non-empty.
- [ ] The chosen approach is well-reasoned and minimal.

## Quality
")"

# ---------------------------------------------------------------------------
# Fixture 5: all-judgment — 5 items, none match mechanical patterns.
# Expected: mechanical_pct=0, judgment_pct=100, recommended_level=system
# ---------------------------------------------------------------------------

PREREG_ALL_JUDGMENT="$(write_prereg fixture-all-judgment "
## Correctness

- [ ] The output narrative is clear and concise.
- [ ] Each claim is supported by evidence from the session.
- [ ] The summary accurately reflects the implementation choices.
- [ ] The self-assessment is honest about uncertainties.
- [ ] The approach deviates minimally from the pre-registered plan.

## Quality
")"

# ---------------------------------------------------------------------------
# Tests: --help
# ---------------------------------------------------------------------------

printf '\n--- criteria-classify: --help ---\n'

help_exit=0
help_out="$(bash "$CLASSIFY" --help 2>&1)" || help_exit=$?

assert_eq "--help exits 0" "0" "$help_exit"
assert_contains "--help mentions usage" "Usage" "$help_out"

# ---------------------------------------------------------------------------
# Tests: fixture 1 — inline (all mechanical)
# ---------------------------------------------------------------------------

printf '\n--- criteria-classify: fixture all-mechanical (inline) ---\n'

out1="$(bash "$CLASSIFY" "$PREREG_ALL_MECHANICAL")"

assert_eq "all-mechanical: recommended_level=inline" \
  '{"mechanical_pct":100,"judgment_pct":0,"recommended_level":"inline"}' \
  "$out1"

# ---------------------------------------------------------------------------
# Tests: fixture 2 — inline (80% mechanical)
# ---------------------------------------------------------------------------

printf '\n--- criteria-classify: fixture mostly-mechanical (inline) ---\n'

out2="$(bash "$CLASSIFY" "$PREREG_MOSTLY_MECHANICAL")"

assert_eq "mostly-mechanical: recommended_level=inline" \
  '{"mechanical_pct":80,"judgment_pct":20,"recommended_level":"inline"}' \
  "$out2"

# ---------------------------------------------------------------------------
# Tests: fixture 3 — unit (40% mechanical)
# ---------------------------------------------------------------------------

printf '\n--- criteria-classify: fixture mixed (unit) ---\n'

out3="$(bash "$CLASSIFY" "$PREREG_MIXED")"

assert_eq "mixed: recommended_level=unit" \
  '{"mechanical_pct":40,"judgment_pct":60,"recommended_level":"unit"}' \
  "$out3"

# ---------------------------------------------------------------------------
# Tests: fixture 4 — system (20% mechanical)
# ---------------------------------------------------------------------------

printf '\n--- criteria-classify: fixture mostly-judgment (system) ---\n'

out4="$(bash "$CLASSIFY" "$PREREG_MOSTLY_JUDGMENT")"

assert_eq "mostly-judgment: recommended_level=system" \
  '{"mechanical_pct":20,"judgment_pct":80,"recommended_level":"system"}' \
  "$out4"

# ---------------------------------------------------------------------------
# Tests: fixture 5 — system (all judgment)
# ---------------------------------------------------------------------------

printf '\n--- criteria-classify: fixture all-judgment (system) ---\n'

out5="$(bash "$CLASSIFY" "$PREREG_ALL_JUDGMENT")"

assert_eq "all-judgment: recommended_level=system" \
  '{"mechanical_pct":0,"judgment_pct":100,"recommended_level":"system"}' \
  "$out5"

# ---------------------------------------------------------------------------
# Fixture 6: indented-Correctness format — mirrors the actual plan.md shape
# (real pre-regs use "  Correctness:" inside a Success criteria block, not
# the "## Correctness" markdown header used in fixtures 1-5). The classifier
# supports both forms.
# Expected: 100% mechanical → inline.
# ---------------------------------------------------------------------------

PREREG_INDENTED="$(write_prereg fixture-indented "
Task ID: T99
Intent: Sample.
Success criteria:
  Correctness:
  - [ ] grep returns at least 3 matches.
  - [ ] exits 0 with valid input.
  - [ ] file exists at the declared path.
  - [ ] wc -l reports ≥ 5 lines.
  Quality:
  - [ ] Code reads cleanly.
")"

printf '\n--- criteria-classify: fixture indented-Correctness (inline) ---\n'

out6="$(bash "$CLASSIFY" "$PREREG_INDENTED")"

assert_eq "indented-Correctness: recommended_level=inline" \
  '{"mechanical_pct":100,"judgment_pct":0,"recommended_level":"inline"}' \
  "$out6"

# ---------------------------------------------------------------------------
# Tests: JSON shape invariants (three keys, values sum to 100, level in enum)
# ---------------------------------------------------------------------------

printf '\n--- criteria-classify: JSON shape invariants ---\n'

# Verify exactly three keys (keys are followed by ":", values are not)
key_count="$(printf '%s' "$out3" | grep -o '"[a-z_]*":' | grep -c .)"
assert_eq "output has exactly 3 keys (checking key patterns)" "3" "$key_count"

# Verify pct values sum to 100
mech_pct="$(printf '%s' "$out3" | grep -o '"mechanical_pct":[0-9]*' | grep -o '[0-9]*$')"
judg_pct="$(printf '%s' "$out3" | grep -o '"judgment_pct":[0-9]*' | grep -o '[0-9]*$')"
pct_sum=$((mech_pct + judg_pct))
assert_eq "mechanical_pct + judgment_pct = 100" "100" "$pct_sum"

# Verify level is one of the three valid enum values
level="$(printf '%s' "$out3" | grep -o '"recommended_level":"[a-z]*"' | grep -o '"[a-z]*"$' | tr -d '"')"
case "$level" in
  inline|unit|system)
    assert_eq "recommended_level is in valid enum" "$level" "$level"
    ;;
  *)
    assert_eq "recommended_level is in valid enum" "inline|unit|system" "$level"
    ;;
esac

# ---------------------------------------------------------------------------
# Tests: edge case — no Correctness block defaults gracefully
# ---------------------------------------------------------------------------

printf '\n--- criteria-classify: no Correctness block ---\n'

PREREG_NO_CORRECTNESS="$(write_prereg fixture-no-correctness "
## Intent

This pre-reg has no Correctness section.

## Quality
")"

out_none="$(bash "$CLASSIFY" "$PREREG_NO_CORRECTNESS")"
assert_eq "no Correctness block: recommended_level=system (0 mechanical)" \
  '{"mechanical_pct":0,"judgment_pct":0,"recommended_level":"system"}' \
  "$out_none"

report
