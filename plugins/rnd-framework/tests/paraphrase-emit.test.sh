#!/usr/bin/env bash
# Tests for lib/paraphrase-emit.sh
# Usage: bash tests/paraphrase-emit.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="${SCRIPT_DIR}/../lib/paraphrase-emit.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SESSION_DIR="${TMP_DIR}/session"
mkdir -p "$SESSION_DIR"

AUDIT_FILE="${SESSION_DIR}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test group: happy path — well-formed event
# ---------------------------------------------------------------------------
printf '%s\n' '--- paraphrase-emit: happy path ---'

RND_DIR="$SESSION_DIR" bash "$EMIT" 14

last_line="$(tail -1 "$AUDIT_FILE")"

event_val="$(printf '%s' "$last_line" | jq -r '.event')"
assert_eq "event field is paraphrase_injected" "paraphrase_injected" "$event_val"

n_val="$(printf '%s' "$last_line" | jq -r '.n_assertions')"
assert_eq "n_assertions field is 14" "14" "$n_val"

ts_val="$(printf '%s' "$last_line" | jq -r '.timestamp')"
assert_contains "timestamp contains T (ISO8601)" "T" "$ts_val"
assert_contains "timestamp ends with Z (UTC)" "Z" "$ts_val"

# ---------------------------------------------------------------------------
# Test group: append-not-overwrite — two invocations yield two lines
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- paraphrase-emit: appends (not overwrites) ---'

RND_DIR="$SESSION_DIR" bash "$EMIT" 5

line_count="$(wc -l < "$AUDIT_FILE" | tr -d ' ')"
assert_eq "audit.jsonl has 2 lines after 2 invocations" "2" "$line_count"

# ---------------------------------------------------------------------------
# Test group: missing RND_DIR → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- paraphrase-emit: missing RND_DIR exits 1 ---'

exit_code=0
bash "$EMIT" 7 2>/dev/null || exit_code=$?

HOOK_EXIT=$exit_code
assert_exit_code "missing RND_DIR → exit 1" 1

# ---------------------------------------------------------------------------
# Test group: missing argument → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- paraphrase-emit: missing argument exits 1 ---'

exit_code2=0
RND_DIR="$SESSION_DIR" bash "$EMIT" 2>/dev/null || exit_code2=$?

HOOK_EXIT=$exit_code2
assert_exit_code "missing argument → exit 1" 1

# ---------------------------------------------------------------------------
# Test group: non-integer argument → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- paraphrase-emit: non-integer argument exits 1 ---'

exit_code3=0
RND_DIR="$SESSION_DIR" bash "$EMIT" "abc" 2>/dev/null || exit_code3=$?

HOOK_EXIT=$exit_code3
assert_exit_code "non-integer argument → exit 1" 1

# ---------------------------------------------------------------------------
report
