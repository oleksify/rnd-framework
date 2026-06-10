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

# Write a protocol.md so plan_summary is non-empty (main pipeline path)
printf 'Task Plan\n=========\nTask 1\nTask 2\nTask 3\n' > "${session_dir}/protocol.md"

# Write a manifest file so current_task_id is detected
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

# Check snake_case fields exist (not camelCase)
for field in plan_summary current_task_id iteration_count saved_at verification_needle; do
  val="$(jq -r ".${field} // \"MISSING\"" "$state_file" 2>/dev/null || printf 'MISSING')"
  if [[ "$val" != "MISSING" ]]; then
    assert_eq "compact-state.json has snake_case field: ${field}" "0" "0"
  else
    assert_eq "compact-state.json has snake_case field: ${field}" "0" "1"
  fi
done

# Confirm no legacy camelCase keys survive in the written record
for old_field in planSummary currentTaskId iterationCount savedAt verificationNeedle; do
  val="$(jq -r "has(\"${old_field}\")" "$state_file" 2>/dev/null || printf 'true')"
  if [[ "$val" = "false" ]]; then
    assert_eq "compact-state.json has no camelCase key: ${old_field}" "0" "0"
  else
    assert_eq "compact-state.json has no camelCase key: ${old_field}" "0" "1"
  fi
done

# plan_summary should contain first lines of protocol.md
plan_summary="$(jq -r '.plan_summary' "$state_file" 2>/dev/null || true)"
assert_contains "plan_summary contains protocol.md content" "Task Plan" "$plan_summary"

# current_task_id should be T1 (from T1-manifest.md — legacy form)
current_task="$(jq -r '.current_task_id // ""' "$state_file" 2>/dev/null || true)"
assert_eq "current_task_id matches manifest basename (legacy form)" "T1" "$current_task"

# iteration_count should be 3 (3 lines in iteration-log.md)
iter_count="$(jq -r '.iteration_count' "$state_file" 2>/dev/null || true)"
assert_eq "iteration_count matches iteration-log line count" "3" "$iter_count"

# verification_needle should be non-empty (random hex)
needle="$(jq -r '.verification_needle // ""' "$state_file" 2>/dev/null || true)"
if [[ -n "$needle" ]]; then
  assert_eq "verification_needle is non-empty" "0" "0"
else
  assert_eq "verification_needle is non-empty" "0" "1"
fi

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# current-format manifest name M<NN>-T<NN>-<8hex>-manifest.md → correct task id
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pre-compact: current-format manifest name recognized ---'

tmp_config_cf="$(mktemp -d)"
base_dir_cf="$(CLAUDE_CONFIG_DIR="$tmp_config_cf" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -n "$base_dir_cf" ]]; then
  session_id_cf="20260101-120000-abcd"
  session_dir_cf="${base_dir_cf}/sessions/${session_id_cf}"
  mkdir -p "${session_dir_cf}/builds"
  printf '%s' "$session_id_cf" > "${base_dir_cf}/.current-session"
  printf 'Task Plan\n' > "${session_dir_cf}/protocol.md"
  touch "${session_dir_cf}/builds/M02-T03-f6d3915b-manifest.md"

  HOOK_EXIT=0
  env "CLAUDE_CONFIG_DIR=${tmp_config_cf}" "$HOOK" > /dev/null 2>&1 || HOOK_EXIT=$?
  assert_eq "pre-compact exits 0 with current-format manifest" "0" "$HOOK_EXIT"

  state_cf="${session_dir_cf}/compact-state.json"
  if [[ -f "$state_cf" ]]; then
    task_cf="$(jq -r '.current_task_id // ""' "$state_cf" 2>/dev/null || true)"
    assert_eq "current_task_id for current-format manifest" "M02-T03-f6d3915b" "$task_cf"
  else
    assert_eq "compact-state.json created for current-format manifest" "0" "1"
  fi
fi

rm -rf "$tmp_config_cf"

# ---------------------------------------------------------------------------
# protocol.md absent → falls back to plan.md
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pre-compact: plan.md fallback ---'

tmp_fallback="$(mktemp -d)"
base_fallback="$(CLAUDE_CONFIG_DIR="$tmp_fallback" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -n "$base_fallback" ]]; then
  session_id_fb="20260101-120000-abcd"
  session_dir_fb="${base_fallback}/sessions/${session_id_fb}"
  mkdir -p "${session_dir_fb}/builds"
  printf '%s' "$session_id_fb" > "${base_fallback}/.current-session"
  printf 'Fallback Plan\n' > "${session_dir_fb}/plan.md"
  touch "${session_dir_fb}/builds/T2-manifest.md"

  HOOK_EXIT=0
  env "CLAUDE_CONFIG_DIR=${tmp_fallback}" "$HOOK" > /dev/null 2>&1 || HOOK_EXIT=$?
  assert_eq "pre-compact exits 0 with plan.md fallback" "0" "$HOOK_EXIT"

  state_fb="${session_dir_fb}/compact-state.json"
  if [[ -f "$state_fb" ]]; then
    plan_fb="$(jq -r '.plan_summary' "$state_fb" 2>/dev/null || true)"
    assert_contains "plan.md fallback: plan_summary populated" "Fallback Plan" "$plan_fb"
  else
    assert_eq "plan.md fallback: compact-state.json created" "0" "1"
  fi
fi

rm -rf "$tmp_fallback"

# ---------------------------------------------------------------------------
# no builds directory → current_task_id is null
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
    task_null="$(jq -r '.current_task_id' "$state2" 2>/dev/null || true)"
    assert_eq "current_task_id is null when no builds dir" "null" "$task_null"
  else
    assert_eq "compact-state.json created with no builds dir" "0" "1"
  fi
fi

rm -rf "$tmp_config2"

report
