#!/usr/bin/env bash
# Tests for lib/replan-emit.sh
# Usage: bash tests/replan-emit.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="${SCRIPT_DIR}/../lib/replan-emit.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SESSION_DIR="${TMP_DIR}/session"
mkdir -p "$SESSION_DIR"

AUDIT_FILE="${SESSION_DIR}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test group: started subcommand
# ---------------------------------------------------------------------------
printf '%s\n' '--- replan-emit: started subcommand ---'

RND_DIR="$SESSION_DIR" "$EMIT" started 1 /tmp/foo

last_line="$(tail -1 "$AUDIT_FILE")"

event_val="$(printf '%s' "$last_line" | jq -r '.event')"
assert_eq "started: event field" "replan_started" "$event_val"

iter_val="$(printf '%s' "$last_line" | jq -r '.iteration')"
assert_eq "started: iteration field" "1" "$iter_val"

archived_val="$(printf '%s' "$last_line" | jq -r '.archived_to')"
assert_eq "started: archived_to field" "/tmp/foo" "$archived_val"

ts_val="$(printf '%s' "$last_line" | jq -r '.timestamp')"
assert_contains "started: timestamp ISO8601" "T" "$ts_val"
assert_contains "started: timestamp UTC Z" "Z" "$ts_val"

# ---------------------------------------------------------------------------
# Test group: diff_emitted subcommand
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-emit: diff_emitted subcommand ---'

RND_DIR="$SESSION_DIR" "$EMIT" diff_emitted 3 7

last_line2="$(tail -1 "$AUDIT_FILE")"

event_val2="$(printf '%s' "$last_line2" | jq -r '.event')"
assert_eq "diff_emitted: event field" "replan_diff_emitted" "$event_val2"

task_changes="$(printf '%s' "$last_line2" | jq -r '.task_changes_count')"
assert_eq "diff_emitted: task_changes_count" "3" "$task_changes"

assertion_changes="$(printf '%s' "$last_line2" | jq -r '.assertion_changes_count')"
assert_eq "diff_emitted: assertion_changes_count" "7" "$assertion_changes"

ts_val2="$(printf '%s' "$last_line2" | jq -r '.timestamp')"
assert_contains "diff_emitted: timestamp present" "T" "$ts_val2"

# ---------------------------------------------------------------------------
# Test group: appends — two lines in audit.jsonl after two invocations
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-emit: both events appended (not overwritten) ---'

line_count="$(wc -l < "$AUDIT_FILE" | tr -d ' ')"
assert_eq "audit.jsonl has 2 lines" "2" "$line_count"

# ---------------------------------------------------------------------------
# Test group: missing RND_DIR → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-emit: missing RND_DIR exits 1 ---'

exit_code=0
bash "$EMIT" started 1 /tmp/foo 2>/dev/null || exit_code=$?

HOOK_EXIT=$exit_code
assert_exit_code "missing RND_DIR → exit 1" 1

# ---------------------------------------------------------------------------
# Test group: fewer than 3 args → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-emit: fewer than 3 args exits 1 ---'

exit_code2=0
RND_DIR="$SESSION_DIR" bash "$EMIT" started 2>/dev/null || exit_code2=$?

HOOK_EXIT=$exit_code2
assert_exit_code "2-arg form → exit 1" 1

# ---------------------------------------------------------------------------
# Test group: unknown subcommand → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-emit: unknown subcommand exits 1 ---'

exit_code3=0
RND_DIR="$SESSION_DIR" bash "$EMIT" badcmd 1 /tmp/foo 2>/dev/null || exit_code3=$?

HOOK_EXIT=$exit_code3
assert_exit_code "unknown subcommand → exit 1" 1

# ---------------------------------------------------------------------------
report
