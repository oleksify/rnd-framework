#!/usr/bin/env bash
# tests/calibration-task-type-window.test.sh — Tests for calibration.sh task_type_window subcommand.
# Usage: bash tests/calibration-task-type-window.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CALIB="${PLUGIN_ROOT}/lib/calibration.sh"

# ---------------------------------------------------------------------------
# Temp environment: isolated calibration.jsonl
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CALIB_DIR="${TMP_DIR}/plugin-data"
mkdir -p "$CALIB_DIR"

CALIB_FILE="${CALIB_DIR}/calibration.jsonl"

# Seed: 5 refactor, 3 bugfix, 2 docs records (mixed criticality)
printf '%s\n' \
  '{"taskId":"T1","criticality":"MEDIUM","verdict":"PASS","task_type":"refactor","falseVerdictFlag":null}' \
  '{"taskId":"T2","criticality":"HIGH","verdict":"PASS","task_type":"refactor","falseVerdictFlag":null}' \
  '{"taskId":"T3","criticality":"LOW","verdict":"PASS","task_type":"refactor","falseVerdictFlag":null}' \
  '{"taskId":"T4","criticality":"MEDIUM","verdict":"FAIL","task_type":"refactor","falseVerdictFlag":null}' \
  '{"taskId":"T5","criticality":"HIGH","verdict":"PASS","task_type":"refactor","falseVerdictFlag":null}' \
  '{"taskId":"T6","criticality":"MEDIUM","verdict":"PASS","task_type":"bugfix","falseVerdictFlag":null}' \
  '{"taskId":"T7","criticality":"LOW","verdict":"FAIL","task_type":"bugfix","falseVerdictFlag":null}' \
  '{"taskId":"T8","criticality":"HIGH","verdict":"PASS","task_type":"bugfix","falseVerdictFlag":null}' \
  '{"taskId":"T9","criticality":"MEDIUM","verdict":"PASS","task_type":"docs","falseVerdictFlag":null}' \
  '{"taskId":"T10","criticality":"LOW","verdict":"PASS","task_type":"docs","falseVerdictFlag":null}' \
  > "$CALIB_FILE"

printf '\n--- task_type_window: basic filtering ---\n'

# task_type_window refactor returns only refactor records
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" task_type_window refactor)"
count="$(printf '%s\n' "$out" | jq -sc 'length')"
assert_eq "task_type_window refactor returns 5 records" "5" "$count"

# task_type_window bugfix returns only bugfix records
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" task_type_window bugfix)"
count="$(printf '%s\n' "$out" | jq -sc 'length')"
assert_eq "task_type_window bugfix returns 3 records" "3" "$count"

# task_type_window docs returns only docs records
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" task_type_window docs)"
count="$(printf '%s\n' "$out" | jq -sc 'length')"
assert_eq "task_type_window docs returns 2 records" "2" "$count"

printf '\n--- task_type_window: N limit ---\n'

# task_type_window refactor 3 returns at most 3 (last 3)
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" task_type_window refactor 3)"
count="$(printf '%s\n' "$out" | jq -sc 'length')"
assert_eq "task_type_window refactor 3 returns 3 records" "3" "$count"

# task_type_window bugfix 2 returns last 2
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" task_type_window bugfix 2)"
count="$(printf '%s\n' "$out" | jq -sc 'length')"
assert_eq "task_type_window bugfix 2 returns 2 records" "2" "$count"

printf '\n--- task_type_window: empty results ---\n'

# task_type_window infra returns empty (no infra records in fixture)
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" task_type_window infra)"
assert_eq "task_type_window infra returns empty" "" "$out"

printf '\n--- task_type_window: missing calibration file ---\n'

# task_type_window on missing file exits 0 and returns empty
EMPTY_DIR="${TMP_DIR}/empty-plugin-data"
mkdir -p "$EMPTY_DIR"
out="$(CLAUDE_PLUGIN_DATA="$EMPTY_DIR" "$CALIB" task_type_window refactor)"
exit_code=0
CLAUDE_PLUGIN_DATA="$EMPTY_DIR" "$CALIB" task_type_window refactor >/dev/null 2>&1 || exit_code=$?
assert_eq "task_type_window missing file exits 0" "0" "$exit_code"
assert_eq "task_type_window missing file returns empty" "" "$out"

printf '\n--- task_type_window: records are valid JSON ---\n'

# Each returned line from task_type_window should be valid JSON with correct task_type
out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" task_type_window refactor)"
all_refactor=1
while IFS= read -r line; do
  tt="$(printf '%s' "$line" | jq -r '.task_type')"
  if [[ "$tt" != "refactor" ]]; then
    all_refactor=0
  fi
done <<< "$out"
assert_eq "task_type_window refactor returns only refactor records (field check)" "1" "$all_refactor"

printf '\n--- calibration --help: task_type_window listed ---\n'

help_out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" --help 2>&1)"
assert_contains "--help lists task_type_window" "task_type_window" "$help_out"

printf '\n--- existing subcommands still work ---\n'

# window subcommand still works
win_out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" window MEDIUM)"
win_count="$(printf '%s\n' "$win_out" | jq -sc 'length')"
assert_eq "window MEDIUM still works" "4" "$win_count"

# false_pass_rate still works
rate="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" false_pass_rate MEDIUM)"
assert_eq "false_pass_rate MEDIUM still works (no false passes = 0.00)" "0.00" "$rate"

# promote_tier still works
tier_out="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" promote_tier LOW)"
assert_eq "promote_tier LOW still works" "MEDIUM" "$tier_out"

# should_promote still exits non-zero (no false passes)
promote_exit=0
CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$CALIB" should_promote MEDIUM || promote_exit=$?
if [[ "$promote_exit" -ne 0 ]]; then
  assert_eq "should_promote exits non-zero (no false passes)" "non-zero" "non-zero"
else
  assert_eq "should_promote exits non-zero (no false passes)" "non-zero" "0"
fi

report
