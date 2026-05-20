#!/usr/bin/env bash
# Tests for lib/audit-event.sh
# Usage: bash tests/audit-event.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="${SCRIPT_DIR}/../lib/audit-event.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SESSION_DIR="${TMP_DIR}/session"
mkdir -p "$SESSION_DIR"

# ---------------------------------------------------------------------------
# Test group: 3-arg form (existing contract unchanged)
# ---------------------------------------------------------------------------
printf '%s\n' '--- audit-event: 3-arg form ---'

AUDIT_FILE_A="${SESSION_DIR}/audit.jsonl"

RND_DIR="$SESSION_DIR" "$AUDIT" test_event_a TASK_A tool_a

record="$(cat "$AUDIT_FILE_A")"

event_val="$(printf '%s' "$record" | jq -r '.event')"
assert_eq "3-arg: event field" "test_event_a" "$event_val"

task_val="$(printf '%s' "$record" | jq -r '.task_id')"
assert_eq "3-arg: task_id field" "TASK_A" "$task_val"

tool_val="$(printf '%s' "$record" | jq -r '.tool')"
assert_eq "3-arg: tool field" "tool_a" "$tool_val"

ts_val="$(printf '%s' "$record" | jq -r '.timestamp')"
assert_contains "3-arg: timestamp present" "T" "$ts_val"

no_assertion="$(printf '%s' "$record" | jq 'has("assertion_id")')"
assert_eq "3-arg: no assertion_id key emitted" "false" "$no_assertion"

# ---------------------------------------------------------------------------
# Test group: 4-arg form (new optional assertion_id)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-event: 4-arg form with assertion_id ---'

SESSION_DIR_4="${TMP_DIR}/session4"
mkdir -p "$SESSION_DIR_4"
AUDIT_FILE_B="${SESSION_DIR_4}/audit.jsonl"

RND_DIR="$SESSION_DIR_4" "$AUDIT" gate_fired TASK_B gate_tool VAL.area.001

record4="$(cat "$AUDIT_FILE_B")"

event_val4="$(printf '%s' "$record4" | jq -r '.event')"
assert_eq "4-arg: event field" "gate_fired" "$event_val4"

task_val4="$(printf '%s' "$record4" | jq -r '.task_id')"
assert_eq "4-arg: task_id field" "TASK_B" "$task_val4"

tool_val4="$(printf '%s' "$record4" | jq -r '.tool')"
assert_eq "4-arg: tool field" "gate_tool" "$tool_val4"

assertion_val="$(printf '%s' "$record4" | jq -r '.assertion_id')"
assert_eq "4-arg: assertion_id field" "VAL.area.001" "$assertion_val"

has_assertion="$(printf '%s' "$record4" | jq 'has("assertion_id")')"
assert_eq "4-arg: assertion_id key present" "true" "$has_assertion"

# ---------------------------------------------------------------------------
# Test group: 4-arg with empty assertion_id → no assertion_id key emitted
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-event: 4-arg with empty assertion_id ---'

SESSION_DIR_E="${TMP_DIR}/session-empty"
mkdir -p "$SESSION_DIR_E"

RND_DIR="$SESSION_DIR_E" "$AUDIT" some_event TASK_C some_tool ""

record_e="$(cat "${SESSION_DIR_E}/audit.jsonl")"

no_key="$(printf '%s' "$record_e" | jq 'has("assertion_id")')"
assert_eq "empty 4th arg: no assertion_id key" "false" "$no_key"

# ---------------------------------------------------------------------------
# Test group: missing RND_DIR → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-event: missing RND_DIR exits 1 ---'

exit_code=0
bash "$AUDIT" test_event TASK tool 2>/dev/null || exit_code=$?

HOOK_EXIT=$exit_code
assert_exit_code "missing RND_DIR → exit 1" 1

# ---------------------------------------------------------------------------
# Test group: fewer than 3 args → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-event: fewer than 3 args exits 1 ---'

exit_code2=0
RND_DIR="$SESSION_DIR" bash "$AUDIT" only_one 2>/dev/null || exit_code2=$?

HOOK_EXIT=$exit_code2
assert_exit_code "2-arg form → exit 1" 1

# ---------------------------------------------------------------------------
report
