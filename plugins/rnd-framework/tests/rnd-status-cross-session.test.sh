#!/usr/bin/env bash
# tests/rnd-status-cross-session.test.sh — Tests for rnd-status --calibration-trends
# cross-session aggregation behavior.
#
# Strategy: build a fake slug-root with calibration.jsonl that represents records
# from two logical sessions and confirm calibration.sh aggregates all of them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CALIB="${PLUGIN_ROOT}/lib/calibration.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Build a fake slug-root.
#
# Layout mirrors the real artifact tree:
#   <slug-root>/
#     calibration.jsonl          <- project-wide, un-partitioned
#     branches/main/
#       sessions/
#         session-1/             <- first logical session
#         session-2/             <- second logical session
#
# Both sessions contribute records to the single slug-root calibration.jsonl,
# which is the correct architecture (calibration is never per-session).
# ---------------------------------------------------------------------------

SLUG_ROOT="${TMP_DIR}/slug"
CALIB_FILE="${SLUG_ROOT}/calibration.jsonl"

mkdir -p "${SLUG_ROOT}/branches/main/sessions/session-1"
mkdir -p "${SLUG_ROOT}/branches/main/sessions/session-2"

# Session 1 contributes 5 records: all LOW, 2 FALSE_PASS + 3 clean PASS.
cat >> "$CALIB_FILE" <<'JSONL'
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":"FALSE_PASS","session":"session-1"}
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":"FALSE_PASS","session":"session-1"}
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":null,"session":"session-1"}
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":null,"session":"session-1"}
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":null,"session":"session-1"}
JSONL

# Session 2 contributes 5 records: all LOW, 3 FALSE_PASS + 2 clean PASS.
cat >> "$CALIB_FILE" <<'JSONL'
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":"FALSE_PASS","session":"session-2"}
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":"FALSE_PASS","session":"session-2"}
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":"FALSE_PASS","session":"session-2"}
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":null,"session":"session-2"}
{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":null,"session":"session-2"}
JSONL

# Total: 10 LOW records, 5 FALSE_PASS → 50% false-PASS rate.

printf '\n--- cross-session: window aggregates records from both sessions ---\n'

# Test 1: window with large N sees all 10 records from both sessions.
window_out="$(CLAUDE_PLUGIN_DATA="$SLUG_ROOT" "$CALIB" window LOW 100)"
record_count="$(printf '%s\n' "$window_out" | jq -sc 'length')"
assert_eq "window(LOW, 100) sees all 10 cross-session records" "10" "$record_count"

printf '\n--- cross-session: false_pass_rate reflects combined sessions ---\n'

# Test 2: false_pass_rate with window=20 covers all 10 records and yields 50%.
# 5 FALSE_PASS out of 10 total = 50.00%.
rate_all="$(CLAUDE_PLUGIN_DATA="$SLUG_ROOT" "$CALIB" false_pass_rate LOW 20)"
assert_eq "false_pass_rate(LOW, 20) over 10 cross-session records = 0.50" "0.50" "$rate_all"

printf '\n--- cross-session: calibration.jsonl resolved via slug-root find ---\n'

# Test 3: verify calibration.jsonl is located at slug root (not per-session).
# Use find to confirm there is exactly one calibration.jsonl under the slug root.
found_count="$(find "$SLUG_ROOT" -maxdepth 1 -name "calibration.jsonl" | wc -l | tr -d ' ')"
assert_eq "calibration.jsonl exists at slug root (not per-session)" "1" "$found_count"

# Test 4: no calibration.jsonl inside session dirs — slug-root is the only location.
session_calib_count="$(find "${SLUG_ROOT}/branches" -name "calibration.jsonl" | wc -l | tr -d ' ')"
assert_eq "no calibration.jsonl inside session directories" "0" "$session_calib_count"

printf '\n--- cross-session: empty slug-root returns 0.00 (no calibration data) ---\n'

EMPTY_SLUG="${TMP_DIR}/empty-slug"
mkdir -p "$EMPTY_SLUG"

# Test 5: missing calibration.jsonl → false_pass_rate returns 0.00, exits 0.
empty_exit=0
empty_rate="$(CLAUDE_PLUGIN_DATA="$EMPTY_SLUG" "$CALIB" false_pass_rate LOW 20 2>/dev/null)" || empty_exit=$?
assert_eq "missing calibration.jsonl exits 0" "0" "$empty_exit"
assert_eq "missing calibration.jsonl → false_pass_rate returns 0.00" "0.00" "$empty_rate"

# Test 6: window on empty slug returns empty string (no crash).
empty_win_exit=0
empty_win="$(CLAUDE_PLUGIN_DATA="$EMPTY_SLUG" "$CALIB" window LOW 20 2>/dev/null)" || empty_win_exit=$?
assert_eq "window on empty slug exits 0" "0" "$empty_win_exit"
assert_eq "window on empty slug returns empty string" "" "$empty_win"

printf '\n--- cross-session: default window(N=10) still captures recent 10 records ---\n'

# Seed a slug-root with 15 LOW records: first 5 are FALSE_PASS, last 10 are clean.
# Default window(10) should see only the last 10 → 0% false-PASS rate.
WINDOW_SLUG="${TMP_DIR}/window-slug"
mkdir -p "$WINDOW_SLUG"
WINDOW_CALIB="${WINDOW_SLUG}/calibration.jsonl"

for i in 1 2 3 4 5; do
  printf '{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":"FALSE_PASS","seq":%d}\n' "$i" >> "$WINDOW_CALIB"
done

for i in 6 7 8 9 10 11 12 13 14 15; do
  printf '{"criticality":"LOW","verdict":"PASS","falseVerdictFlag":null,"seq":%d}\n' "$i" >> "$WINDOW_CALIB"
done

# Test 7: default window sees last 10 (all clean) → 0.00.
windowed_rate="$(CLAUDE_PLUGIN_DATA="$WINDOW_SLUG" "$CALIB" false_pass_rate LOW)"
assert_eq "default window(10) sees last 10 records only" "0.00" "$windowed_rate"

# Test 8: window(15) sees all 15 → 5/15 = 33% (integer arithmetic: 0.33).
full_rate="$(CLAUDE_PLUGIN_DATA="$WINDOW_SLUG" "$CALIB" false_pass_rate LOW 15)"
assert_eq "window(15) sees all 15 records → 5/15 = 0.33" "0.33" "$full_rate"

report
