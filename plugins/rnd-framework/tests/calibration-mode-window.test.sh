#!/usr/bin/env bash
# tests/calibration-mode-window.test.sh — Tests for mode_window, mode_false_pass_rate,
# and collapse_eligible subcommands in lib/calibration.sh.
# Usage: bash tests/calibration-mode-window.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/test-helpers.sh"

CALIB="${PLUGIN_ROOT}/lib/calibration.sh"

# ---------------------------------------------------------------------------
# Temp environment: isolated calibration.jsonl and RND_DIR
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CALIB_DIR="${TMP_DIR}/plugin-data"
mkdir -p "$CALIB_DIR"

SESSION_DIR="${TMP_DIR}/session"
mkdir -p "$SESSION_DIR"

CALIB_FILE="${CALIB_DIR}/calibration.jsonl"

# Fixture layout (chronological order — EARLIER records appear first):
#
#   Lines 1-3:   3 refactor records WITHOUT verification_mode (legacy, treated as prose)
#   Lines 4-23:  20 refactor prose PASS
#   Lines 24-33: 10 refactor prose FALSE_PASS
#   Lines 34-46: 13 refactor property PASS
#   Lines 47-48: 2 refactor property FALSE_PASS
#   Lines 49-53: 5 bugfix prose PASS (task_type isolation)
#
# Placing legacy records FIRST means tail-n-30 of the prose window (33 total)
# captures only the 30 explicit prose records (lines 4-33), so their rates are clean.
#
# collapse_eligible for refactor:
#   prose window (30): 10 FALSE_PASS → 33.33%
#   property window (15): 2 FALSE_PASS → 13.33%
#   threshold = 50% of 33.33 = 16.67 → 13.33 <= 16.67 → eligible

# 3 records with no verification_mode for refactor (backward-compat, treated as prose)
printf '{"task_type":"refactor","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
# 20 refactor prose PASS
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
# 10 refactor prose FALSE_PASS
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
# 13 refactor property PASS
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
# 2 refactor property FALSE_PASS
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
printf '{"task_type":"refactor","verification_mode":"property","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE"
# 5 bugfix prose PASS (task_type isolation)
printf '{"task_type":"bugfix","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"bugfix","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"bugfix","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"bugfix","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"
printf '{"task_type":"bugfix","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE"

printf '\n--- mode_window: filters by task_type AND verification_mode ---\n'

# Assertion 1: mode_window refactor prose 30 returns exactly 30 records (the last 30 of 33 prose)
count="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_window refactor prose 30 | wc -l | tr -d ' ')"
assert_eq "mode_window refactor prose 30 returns 30 records" "30" "$count"

# Assertion 2: mode_window refactor property 30 returns 15 records (all property records)
count="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_window refactor property 30 | wc -l | tr -d ' ')"
assert_eq "mode_window refactor property 30 returns 15 records" "15" "$count"

# Assertion 3: mode_window bugfix prose 30 returns 5 records (task_type isolation)
count="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_window bugfix prose 30 | wc -l | tr -d ' ')"
assert_eq "mode_window bugfix prose 30 returns 5 records (task_type isolation)" "5" "$count"

# Assertion 4: mode_window refactor prose 5 returns at most 5 records (tail/N limit)
count="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_window refactor prose 5 | wc -l | tr -d ' ')"
assert_eq "mode_window refactor prose 5 returns exactly 5 records" "5" "$count"

# Assertion 5: mode_window for unknown task_type returns empty
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_window unknown-type prose 30)"
assert_eq "mode_window for unknown task_type returns empty" "" "$out"

# Assertion 6: records in mode_window refactor prose 30 (last 30 of 33) have explicit
# verification_mode — legacy records are at the front and excluded by tail -n 30
bad="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_window refactor prose 30 \
  | jq -c 'select(.task_type != "refactor" or (.verification_mode // "prose") != "prose")' \
  | wc -l | tr -d ' ')"
assert_eq "mode_window refactor prose records all satisfy task_type AND effective mode" "0" "$bad"

printf '\n--- mode_window: backward-compat for missing verification_mode (treated as prose) ---\n'

# Assertion 7: mode_window refactor prose with large N includes legacy records
# 3 legacy + 20 PASS + 10 FALSE_PASS = 33 total prose records for refactor
count="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_window refactor prose 100 | wc -l | tr -d ' ')"
assert_eq "mode_window refactor prose 100 returns all 33 prose records (includes legacy)" "33" "$count"

printf '\n--- mode_false_pass_rate: returns percent with 2 decimal places ---\n'

# Assertion 8: mode_false_pass_rate refactor prose 30 = 33.33%
# The last 30 prose records: 20 PASS + 10 FALSE_PASS → 10/30 = 33.33
rate="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_false_pass_rate refactor prose 30)"
assert_eq "mode_false_pass_rate refactor prose 30 = 33.33" "33.33" "$rate"

# Assertion 9: mode_false_pass_rate refactor property 30 = 13.33%
# 2 FALSE_PASS out of 15 property records → 2/15 = 13.33
rate="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_false_pass_rate refactor property 30)"
assert_eq "mode_false_pass_rate refactor property 30 = 13.33" "13.33" "$rate"

# Assertion 10: mode_false_pass_rate for empty window returns 0.00
rate="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_false_pass_rate unknown-type prose 30)"
assert_eq "mode_false_pass_rate for empty window returns 0.00" "0.00" "$rate"

# Assertion 11: rate output matches N.NN float format with exactly 2 decimal places
rate="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" mode_false_pass_rate refactor prose 30)"
if [[ "$rate" =~ ^[0-9]+\.[0-9]{2}$ ]]; then
  assert_eq "mode_false_pass_rate output matches NN.NN float format" "matched" "matched"
else
  assert_eq "mode_false_pass_rate output matches NN.NN float format" "matched" "no-match: $rate"
fi

printf '\n--- collapse_eligible: eligible case ---\n'

# collapse_eligible uses a fixed window of 30 records internally.
# prose window (30): 20 PASS + 10 FALSE_PASS → 33.33%; property window (15 all): 2/15 → 13.33%
# threshold = 50% of 33.33 = 16.67; 13.33 <= 16.67 → eligible
result="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" RND_DIR="$SESSION_DIR" "$CALIB" collapse_eligible refactor)"

# Assertion 12: collapse_eligible returns "eligible"
assert_eq "collapse_eligible refactor returns eligible" "eligible" "$result"

# Assertion 13: verifier_collapse_eligible audit event emitted in eligible case
event_count="$(jq -r 'select(.event == "verifier_collapse_eligible") | .event' \
  "${SESSION_DIR}/audit.jsonl" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "verifier_collapse_eligible audit event emitted on eligible" "1" "$event_count"

printf '\n--- collapse_eligible: ineligible due to insufficient samples ---\n'

SESSION2_DIR="${TMP_DIR}/session2"
mkdir -p "$SESSION2_DIR"

# bugfix has only 5 prose records and 0 property records — both windows < 10
result="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" RND_DIR="$SESSION2_DIR" "$CALIB" collapse_eligible bugfix)"

# Assertion 14: returns "ineligible: insufficient samples"
assert_eq "collapse_eligible bugfix returns ineligible: insufficient samples" \
  "ineligible: insufficient samples" "$result"

# Assertion 15: no audit event emitted when insufficient samples
audit2="${SESSION2_DIR}/audit.jsonl"
event_count=0
if [[ -f "$audit2" ]]; then
  event_count="$(jq -r 'select(.event == "verifier_collapse_eligible") | .event' "$audit2" | wc -l | tr -d ' ')"
fi
assert_eq "no audit event when collapse_eligible returns ineligible: insufficient samples" "0" "$event_count"

printf '\n--- collapse_eligible: ineligible due to rate threshold ---\n'

# Build a second fixture where property rate is NOT below 50% of prose rate:
# prose: 10 records, 5 FALSE_PASS → 50.00%; property: 10 records, 5 FALSE_PASS → 50.00%
# threshold = 50% of 50.00 = 25.00; 50.00 > 25.00 → ineligible
CALIB_DIR2="${TMP_DIR}/plugin-data2"
mkdir -p "$CALIB_DIR2"
CALIB_FILE2="${CALIB_DIR2}/calibration.jsonl"

printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"prose","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":"FALSE_PASS"}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"
printf '{"task_type":"new-feature","verification_mode":"property","falseVerdictFlag":null}\n' >> "$CALIB_FILE2"

SESSION3_DIR="${TMP_DIR}/session3"
mkdir -p "$SESSION3_DIR"

result="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR2" RND_DIR="$SESSION3_DIR" "$CALIB" collapse_eligible new-feature)"

# Assertion 16: returns "ineligible: property_rate not below threshold"
assert_eq "collapse_eligible returns ineligible: property_rate not below threshold" \
  "ineligible: property_rate not below threshold" "$result"

# Assertion 17: no audit event emitted when property_rate not below threshold
audit3="${SESSION3_DIR}/audit.jsonl"
event_count=0
if [[ -f "$audit3" ]]; then
  event_count="$(jq -r 'select(.event == "verifier_collapse_eligible") | .event' "$audit3" | wc -l | tr -d ' ')"
fi
assert_eq "no audit event when property_rate not below threshold" "0" "$event_count"

printf '\n--- --help lists new subcommands ---\n'

out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" --help 2>&1)"

# Assertion 18: --help mentions mode_window
assert_contains "--help mentions mode_window" "mode_window" "$out"

# Assertion 19: --help mentions mode_false_pass_rate
assert_contains "--help mentions mode_false_pass_rate" "mode_false_pass_rate" "$out"

# Assertion 20: --help mentions collapse_eligible
assert_contains "--help mentions collapse_eligible" "collapse_eligible" "$out"

report
