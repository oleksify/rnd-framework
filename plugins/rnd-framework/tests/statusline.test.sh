#!/usr/bin/env bash
# tests/statusline.test.sh — Tests for hooks/statusline.sh
# Usage: bash tests/statusline.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/statusline.sh"
RND_DIR_SH="${SCRIPT_DIR}/../lib/rnd-dir.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# Helper: run statusline with given stdin JSON and optional CLAUDE_CONFIG_DIR
run_statusline() {
  local stdin_json="$1"
  local env_override="${2:-}"
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  if [[ -n "$env_override" ]]; then
    printf '%s' "$stdin_json" | env "$env_override" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  else
    printf '%s' "$stdin_json" | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  fi
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# ---------------------------------------------------------------------------
# always outputs {"text":"..."} shape
# ---------------------------------------------------------------------------
printf '%s\n' '--- statusline: output shape ---'

run_statusline '{}'
assert_exit_code "statusline exits 0" 0

if printf '%s' "$HOOK_STDOUT" | jq . > /dev/null 2>&1; then
  assert_eq "statusline outputs valid JSON" "0" "0"
else
  assert_eq "statusline outputs valid JSON" "0" "1"
fi

assert_contains "statusline JSON has text key" '"text"' "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# handles missing rate limits (no rate_limits in input)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- statusline: missing rate limits ---'

run_statusline '{}'
assert_exit_code "statusline exits 0 with empty input" 0
text_no_limits="$(printf '%s' "$HOOK_STDOUT" | jq -r '.text // ""' 2>/dev/null || true)"
# Should not contain "|" (no rate limit parts) — just a phase name
if [[ "$text_no_limits" != *" | "* ]]; then
  assert_eq "statusline text has no rate limit separator when limits absent" "0" "0"
else
  assert_eq "statusline text has no rate limit separator when limits absent" "0" "1"
fi

# ---------------------------------------------------------------------------
# includes rate limit percentages when present
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- statusline: rate limits in output ---'

run_statusline '{"rate_limits":{"fiveHour":{"used_percentage":42.5},"sevenDay":{"used_percentage":18.3}}}'
assert_exit_code "statusline exits 0 with rate limits" 0
text_with_limits="$(printf '%s' "$HOOK_STDOUT" | jq -r '.text // ""' 2>/dev/null || true)"
assert_contains "statusline text contains 5h rate limit" "5h:" "$text_with_limits"
assert_contains "statusline text contains 7d rate limit" "7d:" "$text_with_limits"
assert_contains "statusline text contains separator" " | " "$text_with_limits"

# ---------------------------------------------------------------------------
# phase detection: Idle when no session
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- statusline: phase detection ---'

tmp_no_session="$(mktemp -d)"
run_statusline '{}' "CLAUDE_CONFIG_DIR=${tmp_no_session}"
text_idle="$(printf '%s' "$HOOK_STDOUT" | jq -r '.text // ""' 2>/dev/null || true)"
assert_contains "statusline shows Idle phase when no session" "Idle" "$text_idle"
rm -rf "$tmp_no_session"

# Planning phase: session has plan.md but no builds
tmp_planning="$(mktemp -d)"
base_planning="$(CLAUDE_CONFIG_DIR="$tmp_planning" "$RND_DIR_SH" --base 2>/dev/null || true)"
if [[ -n "$base_planning" ]]; then
  session_plan_id="20260101-120000-abcd"
  session_plan_dir="${base_planning}/sessions/${session_plan_id}"
  mkdir -p "$session_plan_dir"
  printf '%s' "$session_plan_id" > "${base_planning}/.current-session"
  touch "${session_plan_dir}/plan.md"

  run_statusline '{}' "CLAUDE_CONFIG_DIR=${tmp_planning}"
  text_planning="$(printf '%s' "$HOOK_STDOUT" | jq -r '.text // ""' 2>/dev/null || true)"
  assert_contains "statusline shows Planning phase with plan.md" "Planning" "$text_planning"
fi
rm -rf "$tmp_planning"

# Planning phase: session has protocol.md but no builds (main pipeline)
tmp_proto="$(mktemp -d)"
base_proto="$(CLAUDE_CONFIG_DIR="$tmp_proto" "$RND_DIR_SH" --base 2>/dev/null || true)"
if [[ -n "$base_proto" ]]; then
  session_proto_id="20260101-120000-abcd"
  session_proto_dir="${base_proto}/sessions/${session_proto_id}"
  mkdir -p "$session_proto_dir"
  printf '%s' "$session_proto_id" > "${base_proto}/.current-session"
  touch "${session_proto_dir}/protocol.md"

  run_statusline '{}' "CLAUDE_CONFIG_DIR=${tmp_proto}"
  text_proto="$(printf '%s' "$HOOK_STDOUT" | jq -r '.text // ""' 2>/dev/null || true)"
  assert_contains "statusline shows Planning phase with protocol.md" "Planning" "$text_proto"
fi
rm -rf "$tmp_proto"

# Building phase: session has builds/*.md
tmp_building="$(mktemp -d)"
base_building="$(CLAUDE_CONFIG_DIR="$tmp_building" "$RND_DIR_SH" --base 2>/dev/null || true)"
if [[ -n "$base_building" ]]; then
  session_build_id="20260101-120000-abcd"
  session_build_dir="${base_building}/sessions/${session_build_id}"
  mkdir -p "${session_build_dir}/builds"
  printf '%s' "$session_build_id" > "${base_building}/.current-session"
  touch "${session_build_dir}/builds/T1-manifest.md"

  run_statusline '{}' "CLAUDE_CONFIG_DIR=${tmp_building}"
  text_building="$(printf '%s' "$HOOK_STDOUT" | jq -r '.text // ""' 2>/dev/null || true)"
  assert_contains "statusline shows Building phase with builds/*.md" "Building" "$text_building"
fi
rm -rf "$tmp_building"

report
