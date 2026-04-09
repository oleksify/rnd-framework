#!/usr/bin/env bash
# hooks/statusline.sh — Statusline hook: pipeline phase + rate limit display.
# Reads rate_limits from stdin JSON. Outputs {"text":"..."} for Claude Code status bar.
# Always exits 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Pipeline phase names (constants)
readonly PHASE_IDLE="Idle"
readonly PHASE_PLANNING="Planning"
readonly PHASE_BUILDING="Building"
readonly PHASE_VERIFYING="Verifying"
readonly PHASE_INTEGRATING="Integrating"

raw="$(cat)"

# Extract rate limit percentages (round to nearest integer).
five_hour_pct="$(jq_extract "$raw" '.rate_limits.fiveHour.used_percentage')"
seven_day_pct="$(jq_extract "$raw" '.rate_limits.sevenDay.used_percentage')"

# Extract git worktree path (v2.1.97+). Non-empty when cwd is inside a linked worktree.
git_worktree="$(jq_extract "$raw" '.workspace.git_worktree')"

# Detect pipeline phase by checking session directories.
phase="$PHASE_IDLE"
session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -n "$session_dir" ]]; then
  if compgen -G "${session_dir}/integration/"*.md > /dev/null 2>&1; then
    phase="$PHASE_INTEGRATING"
  elif compgen -G "${session_dir}/verifications/"*.md > /dev/null 2>&1; then
    phase="$PHASE_VERIFYING"
  elif compgen -G "${session_dir}/builds/"*.md > /dev/null 2>&1; then
    phase="$PHASE_BUILDING"
  elif [[ -f "${session_dir}/plan.md" ]]; then
    phase="$PHASE_PLANNING"
  fi
fi

# Build rate limit parts string.
parts=""
if [[ -n "$five_hour_pct" ]]; then
  rounded="$(printf '%.0f' "$five_hour_pct" 2>/dev/null || printf '%s' "$five_hour_pct")"
  parts="${parts}5h: ${rounded}%"
fi
if [[ -n "$seven_day_pct" ]]; then
  rounded="$(printf '%.0f' "$seven_day_pct" 2>/dev/null || printf '%s' "$seven_day_pct")"
  [[ -n "$parts" ]] && parts="${parts} | "
  parts="${parts}7d: ${rounded}%"
fi

# Compose final text.
if [[ -n "$parts" ]]; then
  text="${phase} | ${parts}"
else
  text="${phase}"
fi

# Append worktree indicator when inside a linked worktree.
if [[ -n "$git_worktree" ]]; then
  wt_name="${git_worktree##*/}"
  text="${text} [wt: ${wt_name}]"
fi

printf '%s\n' "$(jq -cn --arg t "$text" '{text:$t}')"
exit 0
