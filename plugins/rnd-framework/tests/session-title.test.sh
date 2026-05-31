#!/usr/bin/env bash
# tests/session-title.test.sh — Tests for hooks/session-title.sh
# Usage: bash tests/session-title.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/session-title.sh"
RND_DIR_SH="${SCRIPT_DIR}/../lib/rnd-dir.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# Helper: run session-title with optional CLAUDE_CONFIG_DIR override
run_title() {
  local env_override="${1:-}"
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  if [[ -n "$env_override" ]]; then
    printf '{}' | env "$env_override" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  else
    printf '{}' | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  fi
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# ---------------------------------------------------------------------------
# Basic operation
# ---------------------------------------------------------------------------
printf '%s\n' '--- session-title: basic ---'

run_title
assert_exit_code "exits 0" 0

if printf '%s' "$HOOK_STDOUT" | jq . > /dev/null 2>&1; then
  assert_eq "outputs valid JSON" "0" "0"
else
  assert_eq "outputs valid JSON" "0" "1"
fi

# sessionTitle presence is conditional on an active pipeline session and is
# asserted deterministically in the idle/planning fixtures below — not here,
# where the run uses the ambient config and the active-session state is unknown.

hook_event="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null || true)"
assert_eq "hookEventName is UserPromptSubmit" "UserPromptSubmit" "$hook_event"

has_context="$(printf '%s' "$HOOK_STDOUT" | jq 'has("hookSpecificOutput") and (.hookSpecificOutput | has("additionalContext"))' 2>/dev/null || true)"
assert_eq "additionalContext field present" "true" "$has_context"

# ---------------------------------------------------------------------------
# Idle phase: no active session
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-title: idle phase ---'

tmp_idle="$(mktemp -d)"
run_title "CLAUDE_CONFIG_DIR=${tmp_idle}"
assert_exit_code "no session → exits 0" 0

# No active pipeline → sessionTitle field omitted (no "RND:" branding); Claude
# Code keeps its own auto-generated title.
has_title_idle="$(printf '%s' "$HOOK_STDOUT" | jq '.hookSpecificOutput | has("sessionTitle")' 2>/dev/null || true)"
assert_eq "no session → sessionTitle field omitted" "false" "$has_title_idle"
rm -rf "$tmp_idle"

# ---------------------------------------------------------------------------
# Planning phase: plan.md present (debug pipeline)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-title: planning phase ---'

tmp_plan="$(mktemp -d)"
base_plan="$(CLAUDE_CONFIG_DIR="$tmp_plan" "$RND_DIR_SH" --base 2>/dev/null || true)"
if [[ -n "$base_plan" ]]; then
  session_id="20260101-120000-abcd"
  session_dir="${base_plan}/sessions/${session_id}"
  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_plan}/.current-session"
  touch "${session_dir}/plan.md"

  run_title "CLAUDE_CONFIG_DIR=${tmp_plan}"
  assert_exit_code "planning → exits 0" 0
  title_plan="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.sessionTitle // ""' 2>/dev/null || true)"
  assert_contains "planning → title contains Planning" "Planning" "$title_plan"
fi
rm -rf "$tmp_plan"

# Planning phase: protocol.md present (main pipeline)
tmp_proto="$(mktemp -d)"
base_proto="$(CLAUDE_CONFIG_DIR="$tmp_proto" "$RND_DIR_SH" --base 2>/dev/null || true)"
if [[ -n "$base_proto" ]]; then
  session_id="20260101-120000-abcd"
  session_dir="${base_proto}/sessions/${session_id}"
  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_proto}/.current-session"
  touch "${session_dir}/protocol.md"

  run_title "CLAUDE_CONFIG_DIR=${tmp_proto}"
  assert_exit_code "planning protocol.md → exits 0" 0
  title_proto="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.sessionTitle // ""' 2>/dev/null || true)"
  assert_contains "planning protocol.md → title contains Planning" "Planning" "$title_proto"
fi
rm -rf "$tmp_proto"

# ---------------------------------------------------------------------------
# Resilience: always exits 0 under failure conditions
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-title: resilience ---'

# Broken config dir (stale .active-base-dir)
tmp_broken="$(mktemp -d)"
mkdir -p "${tmp_broken}/.rnd"
printf '/nonexistent/path' > "${tmp_broken}/.rnd/.active-base-dir"

run_title "CLAUDE_CONFIG_DIR=${tmp_broken}"
assert_exit_code "broken cache → exits 0" 0
rm -rf "$tmp_broken"

# Empty stdin
HOOK_EXIT=0
tmp_out="$(mktemp)"
tmp_err="$(mktemp)"
printf '' | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$tmp_out")"
rm -f "$tmp_out" "$tmp_err"
assert_exit_code "empty stdin → exits 0" 0

report
