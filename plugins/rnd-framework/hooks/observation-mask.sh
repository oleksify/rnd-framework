#!/usr/bin/env bash
# hooks/observation-mask.sh — PostToolUse/Bash hook: advises on verbose output.
#
# When Bash output exceeds a threshold (default 50 lines), emits an advisory
# reminding the agent to summarize rather than process raw output.
#
# Always exits 0 — purely advisory, never blocks.
# Skips when no active pipeline session.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LINE_THRESHOLD=50

active_session_dir > /dev/null 2>&1 || exit 0

raw="$(cat)"
stdout="$(printf '%s' "$raw" | jq -r '.stdout // ""' 2>/dev/null || true)"
[[ -n "$stdout" ]] || exit 0

line_count="$(echo "$stdout" | wc -l | tr -d ' ')"
[[ "$line_count" -gt "$LINE_THRESHOLD" ]] || exit 0

advisory_json "Observation mask: Bash output was ${line_count} lines (threshold: ${LINE_THRESHOLD}). Summarize the key signal (pass/fail, errors, counts) in 5-10 lines rather than processing raw output. Verbose observations fill context without proportional value."
exit 0
