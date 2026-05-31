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
# outputs advisory JSON with restored state (snake_case record)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- post-compact: with snake_case state file ---'

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

# Write a compact-state.json with snake_case keys (new format)
jq -cn \
  --arg plan_summary "Task Plan: build widget" \
  --arg current_task_id "T3" \
  --argjson iteration_count 2 \
  --arg saved_at "2026-01-01T12:00:00Z" \
  --arg verification_needle "deadbeef" \
  '{plan_summary:$plan_summary,current_task_id:$current_task_id,iteration_count:$iteration_count,saved_at:$saved_at,verification_needle:$verification_needle}' \
  > "${session_dir}/compact-state.json"

HOOK_EXIT=0
HOOK_OUT="$(env "CLAUDE_CONFIG_DIR=${tmp_config}" "$HOOK" 2>/dev/null || HOOK_EXIT=$?)"
assert_eq "post-compact exits 0 with snake_case state file" "0" "$HOOK_EXIT"

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

# Verification check message must reference protocol.md, not plan.md
assert_contains "post-compact verification check references protocol.md" "protocol.md" "$ctx"

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# legacy camelCase record is still read (back-compat)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- post-compact: legacy camelCase state file ---'

tmp_legacy="$(mktemp -d)"
base_legacy="$(CLAUDE_CONFIG_DIR="$tmp_legacy" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -n "$base_legacy" ]]; then
  session_legacy_id="20260101-120000-abcd"
  session_legacy_dir="${base_legacy}/sessions/${session_legacy_id}"
  mkdir -p "$session_legacy_dir"
  printf '%s' "$session_legacy_id" > "${base_legacy}/.current-session"

  # Write a compact-state.json with legacy camelCase keys
  jq -cn \
    --arg planSummary "Legacy Task Plan" \
    --arg currentTaskId "T7" \
    --argjson iterationCount 5 \
    --arg savedAt "2025-06-01T10:00:00Z" \
    --arg verificationNeedle "cafebabe" \
    '{planSummary:$planSummary,currentTaskId:$currentTaskId,iterationCount:$iterationCount,savedAt:$savedAt,verificationNeedle:$verificationNeedle}' \
    > "${session_legacy_dir}/compact-state.json"

  HOOK_LEGACY_EXIT=0
  HOOK_LEGACY_OUT="$(env "CLAUDE_CONFIG_DIR=${tmp_legacy}" "$HOOK" 2>/dev/null || HOOK_LEGACY_EXIT=$?)"
  assert_eq "post-compact exits 0 with legacy camelCase state" "0" "$HOOK_LEGACY_EXIT"

  ctx_legacy="$(printf '%s' "$HOOK_LEGACY_OUT" | jq -r '.systemMessage // ""' 2>/dev/null || true)"
  assert_contains "legacy record: task id restored" "T7" "$ctx_legacy"
  assert_contains "legacy record: iteration count restored" "5" "$ctx_legacy"
  assert_contains "legacy record: needle restored" "cafebabe" "$ctx_legacy"
fi

rm -rf "$tmp_legacy"

report
