#!/usr/bin/env bash
# Tests for lib/premortem-emit.sh
# Usage: bash tests/premortem-emit.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/../lib/premortem-emit.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Test group: JSON shape for "a,b,c" / 9
# ---------------------------------------------------------------------------
printf '%s\n' '--- premortem-emit: JSON shape ---'

SESSION_DIR="${TMP_DIR}/session-shape"
mkdir -p "$SESSION_DIR"

RND_DIR="$SESSION_DIR" "$SCRIPT" "a,b,c" "9"

record="$(cat "${SESSION_DIR}/audit.jsonl")"

event_val="$(printf '%s' "$record" | jq -r '.event')"
assert_eq "event == premortem_generated" "premortem_generated" "$event_val"

framings_val="$(printf '%s' "$record" | jq -c '.framings')"
assert_eq "framings == [\"a\",\"b\",\"c\"]" '["a","b","c"]' "$framings_val"

fmc_val="$(printf '%s' "$record" | jq -r '.failure_mode_count')"
assert_eq "failure_mode_count == 9 (number)" "9" "$fmc_val"

fmc_type="$(printf '%s' "$record" | jq -r '(.failure_mode_count | type)')"
assert_eq "failure_mode_count is number type" "number" "$fmc_type"

ts_val="$(printf '%s' "$record" | jq -r '.timestamp')"
ts_match="$(printf '%s' "$ts_val" | grep -c '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z$' || true)"
assert_eq "timestamp matches ISO8601Z" "1" "$ts_match"

line_count="$(wc -l < "${SESSION_DIR}/audit.jsonl" | tr -d ' ')"
assert_eq "exactly one line appended" "1" "$line_count"

# ---------------------------------------------------------------------------
# Test group: n is computed from framings (5 framings)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- premortem-emit: n computed from framings (5) ---'

SESSION_DIR_5="${TMP_DIR}/session-n5"
mkdir -p "$SESSION_DIR_5"

RND_DIR="$SESSION_DIR_5" "$SCRIPT" "a,b,c,d,e" "0"

record5="$(cat "${SESSION_DIR_5}/audit.jsonl")"

n5="$(printf '%s' "$record5" | jq -r '.n')"
assert_eq "n == 5 for 5-element CSV" "5" "$n5"

n5_type="$(printf '%s' "$record5" | jq -r '(.n | type)')"
assert_eq "n is number type (5)" "number" "$n5_type"

# ---------------------------------------------------------------------------
# Test group: n is computed from framings (3 framings)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- premortem-emit: n computed from framings (3) ---'

SESSION_DIR_3="${TMP_DIR}/session-n3"
mkdir -p "$SESSION_DIR_3"

RND_DIR="$SESSION_DIR_3" "$SCRIPT" "a,b,c" "7"

record3="$(cat "${SESSION_DIR_3}/audit.jsonl")"

n3="$(printf '%s' "$record3" | jq -r '.n')"
assert_eq "n == 3 for 3-element CSV" "3" "$n3"

# ---------------------------------------------------------------------------
# Test group: missing RND_DIR → exit 1, no audit line
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- premortem-emit: missing RND_DIR exits 1 ---'

exit_code=0
bash "$SCRIPT" "a,b" "2" 2>/dev/null || exit_code=$?

HOOK_EXIT=$exit_code
assert_exit_code "missing RND_DIR → exit 1" 1

# ---------------------------------------------------------------------------
report
