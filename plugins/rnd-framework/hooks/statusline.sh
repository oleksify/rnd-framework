#!/usr/bin/env bash
# hooks/statusline.sh — Statusline hook: pipeline phase + rate limit display.
# Reads rate_limits from stdin JSON. Outputs {"text":"..."} for Claude Code status bar.
# Always exits 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"

# Extract rate limit percentages (round to nearest integer).
five_hour_pct="$(jq_extract "$raw" '.rate_limits.fiveHour.used_percentage')"
seven_day_pct="$(jq_extract "$raw" '.rate_limits.sevenDay.used_percentage')"

session_dir="$(active_session_dir 2>/dev/null || true)"
phase="$(detect_pipeline_phase "$session_dir")"

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

printf '%s\n' "$(jq -cn --arg t "$text" '{text:$t}')"
exit 0
