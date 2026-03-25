#!/usr/bin/env bash
# tests/pre-compact.test.sh — Tests for hooks/pre-compact.sh
# Usage: bash tests/pre-compact.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/pre-compact.sh"
RND_DIR_SH="${SCRIPT_DIR}/../lib/rnd-dir.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# exits 0 when no session is active
# ---------------------------------------------------------------------------
printf '%s\n' '--- pre-compact: no active session ---'

tmp_no_session="$(mktemp -d)"
HOOK_EXIT=0
env "CLAUDE_CONFIG_DIR=${tmp_no_session}" "$HOOK" > /dev/null 2>&1 || HOOK_EXIT=$?
assert_eq "pre-compact exits 0 when no session" "0" "$HOOK_EXIT"

rm -rf "$tmp_no_session"

# ---------------------------------------------------------------------------
# writes compact-state.json with expected fields when session is active
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pre-compact: active session ---'

tmp_config="$(mktemp -d)"

# Resolve the actual slug rnd-dir.sh computes for this directory
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -z "$base_dir" ]]; then
  assert_eq "pre-compact: could not resolve base_dir (skipping session tests)" "0" "1"
  rm -rf "$tmp_config"
  report
  exit $?
fi

session_id="20260101-120000-abcd"
session_dir="${base_dir}/sessions/${session_id}"
mkdir -p "${session_dir}/builds"
printf '%s' "$session_id" > "${base_dir}/.current-session"

# Write a plan.md so planSummary is non-empty
printf 'Task Plan\n=========\nTask 1\nTask 2\nTask 3\n' > "${session_dir}/plan.md"

# Write a manifest file so currentTaskId is detected
touch "${session_dir}/builds/T1-manifest.md"

# Write an iteration log (3 lines)
printf 'line1\nline2\nline3\n' > "${session_dir}/iteration-log.md"

HOOK_EXIT=0
env "CLAUDE_CONFIG_DIR=${tmp_config}" "$HOOK" > /dev/null 2>&1 || HOOK_EXIT=$?
assert_eq "pre-compact exits 0 with active session" "0" "$HOOK_EXIT"

state_file="${session_dir}/compact-state.json"
if [[ -f "$state_file" ]]; then
  assert_eq "compact-state.json is created" "0" "0"
else
  assert_eq "compact-state.json is created" "0" "1"
fi

# Validate JSON structure
if [[ -f "$state_file" ]] && jq . "$state_file" > /dev/null 2>&1; then
  assert_eq "compact-state.json is valid JSON" "0" "0"
else
  assert_eq "compact-state.json is valid JSON" "0" "1"
fi

# Check required fields exist
for field in planSummary currentTaskId iterationCount savedAt verificationNeedle; do
  val="$(jq -r ".${field} // \"MISSING\"" "$state_file" 2>/dev/null || printf 'MISSING')"
  if [[ "$val" != "MISSING" ]]; then
    assert_eq "compact-state.json has field: ${field}" "0" "0"
  else
    assert_eq "compact-state.json has field: ${field}" "0" "1"
  fi
done

# planSummary should contain first lines of plan.md
plan_summary="$(jq -r '.planSummary' "$state_file" 2>/dev/null || true)"
assert_contains "planSummary contains plan content" "Task Plan" "$plan_summary"

# currentTaskId should be T1 (from T1-manifest.md)
current_task="$(jq -r '.currentTaskId // ""' "$state_file" 2>/dev/null || true)"
assert_eq "currentTaskId matches manifest basename" "T1" "$current_task"

# iterationCount should be 3 (3 lines in iteration-log.md)
iter_count="$(jq -r '.iterationCount' "$state_file" 2>/dev/null || true)"
assert_eq "iterationCount matches iteration-log line count" "3" "$iter_count"

# verificationNeedle should be non-empty (random hex)
needle="$(jq -r '.verificationNeedle // ""' "$state_file" 2>/dev/null || true)"
if [[ -n "$needle" ]]; then
  assert_eq "verificationNeedle is non-empty" "0" "0"
else
  assert_eq "verificationNeedle is non-empty" "0" "1"
fi

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# no builds directory → currentTaskId is null
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pre-compact: no builds dir ---'

tmp_config2="$(mktemp -d)"
base_dir2="$(CLAUDE_CONFIG_DIR="$tmp_config2" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -n "$base_dir2" ]]; then
  session_id2="20260101-130000-abcd"
  session_dir2="${base_dir2}/sessions/${session_id2}"
  mkdir -p "$session_dir2"
  printf '%s' "$session_id2" > "${base_dir2}/.current-session"
  printf 'Minimal plan\n' > "${session_dir2}/plan.md"

  HOOK_EXIT=0
  env "CLAUDE_CONFIG_DIR=${tmp_config2}" "$HOOK" > /dev/null 2>&1 || HOOK_EXIT=$?
  assert_eq "pre-compact exits 0 with no builds dir" "0" "$HOOK_EXIT"

  state2="${session_dir2}/compact-state.json"
  if [[ -f "$state2" ]]; then
    task_null="$(jq -r '.currentTaskId' "$state2" 2>/dev/null || true)"
    assert_eq "currentTaskId is null when no builds dir" "null" "$task_null"
  else
    assert_eq "compact-state.json created with no builds dir" "0" "1"
  fi
fi

rm -rf "$tmp_config2"

report
