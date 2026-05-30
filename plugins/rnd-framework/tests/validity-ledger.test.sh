#!/usr/bin/env bash
# tests/validity-ledger.test.sh — Tests for lib/calibration.sh per-shape
# validity ledger (consecutive_clean + validity subcommands).
# Usage: bash tests/validity-ledger.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CALIB="${PLUGIN_ROOT}/lib/calibration.sh"

# ---------------------------------------------------------------------------
# Isolated slug-root: post-review.jsonl lives alongside calibration.jsonl.
# CLAUDE_PLUGIN_DATA pins that root so no real artifact tree is touched.
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# A finding row: a (session, shape) with at least one review_found:true.
finding_row() {
  local session="$1" shape="$2" severity="$3"
  printf '{"shape":"%s","severity":"%s","verifier_said_PASS":false,"review_found":true,"session_id":"%s","timestamp":"%s"}\n' \
    "$shape" "$severity" "$session" "$session"
}

# A clean row: a (session, shape) with review_found:false.
clean_row() {
  local session="$1" shape="$2"
  printf '{"shape":"%s","severity":"none","verifier_said_PASS":true,"review_found":false,"session_id":"%s","timestamp":"%s"}\n' \
    "$shape" "$session" "$session"
}

# Build a fresh isolated plugin-data dir seeded from stdin (jsonl); echo the dir.
seed_postreview() {
  local dir
  dir="$(mktemp -d "${TMP_DIR}/data.XXXXXX")"
  cat > "${dir}/post-review.jsonl"
  printf '%s' "$dir"
}

run_validity() {
  local dir="$1" shape="$2"
  RUN_EXIT=0
  RUN_OUT="$(CLAUDE_PLUGIN_DATA="$dir" "$CALIB" validity "$shape" 2>&1)" || RUN_EXIT=$?
}

run_consecutive() {
  local dir="$1" shape="$2"
  RUN_EXIT=0
  RUN_OUT="$(CLAUDE_PLUGIN_DATA="$dir" "$CALIB" consecutive_clean "$shape" 2>&1)" || RUN_EXIT=$?
}

printf '\n--- validity-ledger: grain collapse ---\n'

# (a) one 2-finding session + one clean session over a shape → streak 1, not 2.
DIR_A="$(
  {
    finding_row "20260101-000000-aaaa" wiring critical
    finding_row "20260101-000000-aaaa" wiring minor
    clean_row   "20260102-000000-bbbb" wiring
  } | seed_postreview
)"
run_consecutive "$DIR_A" wiring
assert_eq "2-finding session + clean session → consecutive-clean 1" "1" "$RUN_OUT"

printf '\n--- validity-ledger: expert threshold ---\n'

# (b) 5 consecutive clean → expert (exit 0).
DIR_B="$(
  {
    clean_row "20260101-000000-0001" wiring
    clean_row "20260102-000000-0002" wiring
    clean_row "20260103-000000-0003" wiring
    clean_row "20260104-000000-0004" wiring
    clean_row "20260105-000000-0005" wiring
  } | seed_postreview
)"
run_validity "$DIR_B" wiring
assert_eq      "5 clean → validity exit 0"     "0"       "$RUN_EXIT"
assert_contains "5 clean → prints expert"      "expert"  "$RUN_OUT"

# (c) 4 clean → novice (exit non-zero).
DIR_C="$(
  {
    clean_row "20260101-000000-0001" wiring
    clean_row "20260102-000000-0002" wiring
    clean_row "20260103-000000-0003" wiring
    clean_row "20260104-000000-0004" wiring
  } | seed_postreview
)"
run_validity "$DIR_C" wiring
assert_eq      "4 clean → validity exit 1"     "1"        "$RUN_EXIT"
assert_contains "4 clean → prints novice"      "novice"   "$RUN_OUT"

# (d) 4 clean + 1 dirty + 1 clean → trailing streak 1, not expert.
DIR_D="$(
  {
    clean_row   "20260101-000000-0001" wiring
    clean_row   "20260102-000000-0002" wiring
    clean_row   "20260103-000000-0003" wiring
    clean_row   "20260104-000000-0004" wiring
    finding_row "20260105-000000-0005" wiring major
    clean_row   "20260106-000000-0006" wiring
  } | seed_postreview
)"
run_consecutive "$DIR_D" wiring
assert_eq "dirty mid-stream breaks streak → trailing 1" "1" "$RUN_OUT"
run_validity "$DIR_D" wiring
assert_eq "dirty mid-stream → not expert (exit 1)" "1" "$RUN_EXIT"

printf '\n--- validity-ledger: one-strike reset, no state file ---\n'

# (e) 5 clean (expert), append one dirty finding row, re-invoke → NOT expert.
DIR_E="$(
  {
    clean_row "20260101-000000-0001" wiring
    clean_row "20260102-000000-0002" wiring
    clean_row "20260103-000000-0003" wiring
    clean_row "20260104-000000-0004" wiring
    clean_row "20260105-000000-0005" wiring
  } | seed_postreview
)"
run_validity "$DIR_E" wiring
assert_eq "expert before dirty append (exit 0)" "0" "$RUN_EXIT"

# Append a single dirty finding row from a newer session; recompute must reset.
finding_row "20260106-000000-0006" wiring critical >> "${DIR_E}/post-review.jsonl"
run_validity "$DIR_E" wiring
assert_eq "one-strike: dirty append → not expert (exit 1)" "1" "$RUN_EXIT"

# No persisted streak-state artifact may exist — only post-review.jsonl.
state_files="$(find "$DIR_E" -type f ! -name 'post-review.jsonl' | wc -l | tr -d ' ')"
assert_eq "no streak-state file written" "0" "$state_files"

printf '\n--- validity-ledger: file-absent graceful ---\n'

# (f) file absent → graceful: novice, exit non-zero, no crash.
DIR_F="$(mktemp -d "${TMP_DIR}/data.XXXXXX")"
run_validity "$DIR_F" wiring
assert_eq "file absent → validity exit 1" "1" "$RUN_EXIT"
run_consecutive "$DIR_F" wiring
assert_eq "file absent → consecutive_clean prints 0" "0"  "$RUN_OUT"
assert_eq "file absent → consecutive_clean exit 0"   "0"  "$RUN_EXIT"

printf '\n--- validity-ledger: --help and isolation ---\n'

# --help mentions the new subcommands and exits 0.
help_exit=0
help_out="$("$CALIB" --help 2>&1)" || help_exit=$?
assert_eq      "--help exits 0"                 "0"                 "$help_exit"
assert_contains "--help mentions validity"      "validity"          "$help_out"
assert_contains "--help mentions consecutive"   "consecutive_clean" "$help_out"

report
