#!/usr/bin/env bash
# Tests for lib/outside-view-emit.sh
# Usage: bash tests/outside-view-emit.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMITTER="${SCRIPT_DIR}/../lib/outside-view-emit.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Test group: script exists and is executable, has usage line
# ---------------------------------------------------------------------------
printf '%s\n' '--- outside-view-emit: script metadata ---'

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ -x "$EMITTER" ]]; then
  printf '  PASS  script is executable\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  script is not executable: %s\n' "$EMITTER"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

has_usage=0
grep -qE 'Usage:.*outside-view-emit\.sh' "$EMITTER" && has_usage=1
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ $has_usage -eq 1 ]]; then
  printf '  PASS  usage line present\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  usage line missing (expected pattern: Usage:.*outside-view-emit\.sh)\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Test group: payload schema
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-emit: payload schema ---'

SESSION_DIR="${TMP_DIR}/session"
mkdir -p "$SESSION_DIR"
AUDIT_FILE="${SESSION_DIR}/audit.jsonl"

RND_DIR="$SESSION_DIR" "$EMITTER" thin-corpus 4 '[{"shape":"crud","task_count":2,"fail_count":0}]' true

line_count="$(wc -l < "$AUDIT_FILE" | tr -d ' ')"
assert_eq "exactly one line appended" "1" "$line_count"

record="$(cat "$AUDIT_FILE")"

event_val="$(printf '%s' "$record" | jq -r '.event')"
assert_eq "event == outside_view_injected" "outside_view_injected" "$event_val"

mode_val="$(printf '%s' "$record" | jq -r '.mode')"
assert_eq "mode == thin-corpus" "thin-corpus" "$mode_val"

n_total_val="$(printf '%s' "$record" | jq -r '.n_total')"
assert_eq "n_total == 4 (number)" "4" "$n_total_val"

n_total_type="$(printf '%s' "$record" | jq -r '.n_total | type')"
assert_eq "n_total is number type" "number" "$n_total_type"

shapes_len="$(printf '%s' "$record" | jq -r '.shapes | length')"
assert_eq "shapes has 1 element" "1" "$shapes_len"

shape_val="$(printf '%s' "$record" | jq -r '.shapes[0].shape')"
assert_eq "shapes[0].shape == crud" "crud" "$shape_val"

framing_val="$(printf '%s' "$record" | jq -r '.framing_constraint_emitted')"
assert_eq "framing_constraint_emitted == true" "true" "$framing_val"

framing_type="$(printf '%s' "$record" | jq -r '.framing_constraint_emitted | type')"
assert_eq "framing_constraint_emitted is boolean type" "boolean" "$framing_type"

ts_val="$(printf '%s' "$record" | jq -r '.timestamp')"
assert_contains "timestamp contains T (ISO-8601)" "T" "$ts_val"
assert_contains "timestamp contains Z (Zulu)" "Z" "$ts_val"

# ---------------------------------------------------------------------------
# Test group: append-only (second call adds second line, not overwrites)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-emit: append-only ---'

SESSION_DIR_2="${TMP_DIR}/session2"
mkdir -p "$SESSION_DIR_2"

RND_DIR="$SESSION_DIR_2" "$EMITTER" full-corpus 2 '[]' false
RND_DIR="$SESSION_DIR_2" "$EMITTER" thin-corpus 1 '[]' true

line_count2="$(wc -l < "${SESSION_DIR_2}/audit.jsonl" | tr -d ' ')"
assert_eq "two calls → two lines (append-only)" "2" "$line_count2"

# ---------------------------------------------------------------------------
# Test group: false for framing_constraint_emitted
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-emit: false boolean ---'

SESSION_DIR_3="${TMP_DIR}/session3"
mkdir -p "$SESSION_DIR_3"

RND_DIR="$SESSION_DIR_3" "$EMITTER" full-corpus 0 '[]' false

framing_false="$(jq -r '.framing_constraint_emitted' "${SESSION_DIR_3}/audit.jsonl")"
assert_eq "framing_constraint_emitted == false (boolean)" "false" "$framing_false"

framing_false_type="$(jq -r '.framing_constraint_emitted | type' "${SESSION_DIR_3}/audit.jsonl")"
assert_eq "framing_constraint_emitted false is boolean type" "boolean" "$framing_false_type"

# ---------------------------------------------------------------------------
# Test group: missing RND_DIR → exit non-zero with RND_DIR in stderr
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-emit: missing RND_DIR ---'

err_file="${TMP_DIR}/err.txt"
exit_code=0
bash "$EMITTER" thin-corpus 0 '[]' false 2>"$err_file" || exit_code=$?

HOOK_EXIT=$exit_code
assert_exit_code "unset RND_DIR → exit non-zero" 1

err_contents="$(cat "$err_file")"
assert_contains "stderr mentions RND_DIR" "RND_DIR" "$err_contents"

# ---------------------------------------------------------------------------
report
