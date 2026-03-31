#!/usr/bin/env bash
# tests/post-compact.test.sh — Tests for hooks/post-compact.sh
# Usage: bash tests/post-compact.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/post-compact.sh"
RND_DIR_SH="${SCRIPT_DIR}/../lib/rnd-dir.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# exits 0 when no session is active
# ---------------------------------------------------------------------------
printf '%s\n' '--- post-compact: no active session ---'

tmp_no_session="$(mktemp -d)"
HOOK_EXIT=0
HOOK_OUT="$(env "CLAUDE_CONFIG_DIR=${tmp_no_session}" "$HOOK" 2>/dev/null || HOOK_EXIT=$?)"
assert_eq "post-compact exits 0 when no session" "0" "$HOOK_EXIT"
assert_eq "post-compact no output when no session" "" "$HOOK_OUT"

rm -rf "$tmp_no_session"

# ---------------------------------------------------------------------------
# exits 0 when no state file exists
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- post-compact: no state file ---'

tmp_no_state="$(mktemp -d)"
base_dir_no_state="$(CLAUDE_CONFIG_DIR="$tmp_no_state" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -n "$base_dir_no_state" ]]; then
  session_id="20260101-140000-abcd"
  session_dir="${base_dir_no_state}/sessions/${session_id}"
  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_dir_no_state}/.current-session"
  # No compact-state.json written

  HOOK_EXIT=0
  HOOK_OUT="$(env "CLAUDE_CONFIG_DIR=${tmp_no_state}" "$HOOK" 2>/dev/null || HOOK_EXIT=$?)"
  assert_eq "post-compact exits 0 when no state file" "0" "$HOOK_EXIT"
  assert_eq "post-compact no output when no state file" "" "$HOOK_OUT"
fi

rm -rf "$tmp_no_state"

# ---------------------------------------------------------------------------
# outputs advisory JSON with restored state when state file exists
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- post-compact: with state file ---'

tmp_config="$(mktemp -d)"
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -z "$base_dir" ]]; then
  assert_eq "post-compact: could not resolve base_dir (skipping)" "0" "1"
  rm -rf "$tmp_config"
  report
  exit $?
fi

session_id="20260101-120000-abcd"
session_dir="${base_dir}/sessions/${session_id}"
mkdir -p "$session_dir"
printf '%s' "$session_id" > "${base_dir}/.current-session"

# Write a compact-state.json
jq -cn \
  --arg planSummary "Task Plan: build widget" \
  --arg currentTaskId "T3" \
  --argjson iterationCount 2 \
  --arg savedAt "2026-01-01T12:00:00Z" \
  --arg verificationNeedle "deadbeef" \
  '{planSummary:$planSummary,currentTaskId:$currentTaskId,iterationCount:$iterationCount,savedAt:$savedAt,verificationNeedle:$verificationNeedle}' \
  > "${session_dir}/compact-state.json"

HOOK_EXIT=0
HOOK_OUT="$(env "CLAUDE_CONFIG_DIR=${tmp_config}" "$HOOK" 2>/dev/null || HOOK_EXIT=$?)"
assert_eq "post-compact exits 0 with state file" "0" "$HOOK_EXIT"

# Output must be valid JSON
if printf '%s' "$HOOK_OUT" | jq . > /dev/null 2>&1; then
  assert_eq "post-compact output is valid JSON" "0" "0"
else
  assert_eq "post-compact output is valid JSON" "0" "1"
fi

# Output must be a system message (contains systemMessage)
assert_contains "post-compact output contains systemMessage" '"systemMessage"' "$HOOK_OUT"

# System message text must mention plan and task
ctx="$(printf '%s' "$HOOK_OUT" | jq -r '.systemMessage // ""' 2>/dev/null || true)"
assert_contains "post-compact system message mentions plan content" "Task Plan" "$ctx"
assert_contains "post-compact system message mentions current task" "T3" "$ctx"

# System message text must mention the needle for verification challenge
assert_contains "post-compact system message contains verification needle" "deadbeef" "$ctx"

rm -rf "$tmp_config"

report
