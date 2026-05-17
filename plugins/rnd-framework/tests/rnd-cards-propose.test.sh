#!/usr/bin/env bash
# tests/rnd-cards-propose.test.sh — Tests for lib/rnd-cards-propose.sh
# Usage: bash tests/rnd-cards-propose.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

PROPOSE="${PLUGIN_ROOT}/lib/rnd-cards-propose.sh"

# ---------------------------------------------------------------------------
# Temp environment
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CALIB_FILE="${TMP_DIR}/calibration.jsonl"

# Seed fixture: 5 FAIL records sharing multiple 4-grams (Jaccard >= 0.4 between
# every pair), plus 3 singleton FAIL records with 1-3 word feedback (no 4-grams).
#
# Each clustered record has 6 words: first 5 are identical ("missing required
# field in response"), last word differs. This produces 3 4-grams per record
# where the first 2 ("missing required field in" and "required field in
# response") are shared across all 5. Jaccard between any pair = 2/4 = 0.5,
# which exceeds the default threshold of 0.4.
#
# The 3 singleton records have 1-2 word feedback: no 4-grams are possible, so
# they produce empty ngram sets and never link to anything.

cat > "$CALIB_FILE" <<'JSONL'
{"verdict":"FAIL","feedback":"missing required field in response body"}
{"verdict":"FAIL","feedback":"missing required field in response payload"}
{"verdict":"FAIL","feedback":"missing required field in response data"}
{"verdict":"NEEDS_ITERATION","feedback":"missing required field in response object"}
{"verdict":"FAIL","feedback":"missing required field in response structure"}
{"verdict":"FAIL","feedback":"timeout"}
{"verdict":"FAIL","feedback":"null pointer"}
{"verdict":"FAIL","feedback":"auth error"}
JSONL

printf '\n--- rnd-cards-propose: basic clustering (5 clustered + 3 singletons) ---\n'

# Default threshold 0.4 should produce exactly 1 cluster heading.
out="$(bash "$PROPOSE" --calibration="$CALIB_FILE")"

cluster_count="$(printf '%s' "$out" | grep -c '^## Cluster ' || true)"
assert_eq "exactly 1 cluster surfaces at default threshold" "1" "$cluster_count"

printf '\n--- rnd-cards-propose: cluster size reported correctly ---\n'

assert_contains "cluster size line present" "**Cluster size:** 5" "$out"

printf '\n--- rnd-cards-propose: draft card scaffold present ---\n'

assert_contains "scaffold has role field" "role: builder" "$out"
assert_contains "scaffold has tags field" "tags: []" "$out"

printf '\n--- rnd-cards-propose: threshold override (0.99 → 0 clusters) ---\n'

# At threshold 0.99 no two feedbacks in the fixture are similar enough to link.
out_high="$(bash "$PROPOSE" --calibration="$CALIB_FILE" --threshold=0.99)"

cluster_count_high="$(printf '%s' "$out_high" | grep -c '^## Cluster ' || true)"
assert_eq "0 clusters at threshold 0.99" "0" "$cluster_count_high"

printf '\n--- rnd-cards-propose: PASS records excluded ---\n'

CALIB_PASS_ONLY="${TMP_DIR}/pass-only.jsonl"
cat > "$CALIB_PASS_ONLY" <<'JSONL'
{"verdict":"PASS","feedback":"all good"}
{"verdict":"PASS","feedback":"all good"}
{"verdict":"PASS","feedback":"all good"}
JSONL

out_pass="$(bash "$PROPOSE" --calibration="$CALIB_PASS_ONLY")"
cluster_count_pass="$(printf '%s' "$out_pass" | grep -c '^## Cluster ' || true)"
assert_eq "PASS-only file produces 0 clusters" "0" "$cluster_count_pass"

printf '\n--- rnd-cards-propose: missing calibration file exits gracefully ---\n'

out_missing="$(bash "$PROPOSE" --calibration="${TMP_DIR}/nonexistent.jsonl")"
cluster_count_missing="$(printf '%s' "$out_missing" | grep -c '^## Cluster ' || true)"
assert_eq "missing calibration file produces 0 clusters" "0" "$cluster_count_missing"

printf '\n--- rnd-cards-propose: --help exits 0 ---\n'

help_exit=0
bash "$PROPOSE" --help >/dev/null 2>&1 || help_exit=$?
assert_eq "--help exits 0" "0" "$help_exit"

report
