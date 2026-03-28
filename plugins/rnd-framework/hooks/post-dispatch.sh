#!/usr/bin/env bash
# hooks/post-dispatch.sh — Unified PostToolUse hook.
#
# Merged from post-tool-use.sh + observation-mask.sh into a single dispatcher.
# Fast-path: exits immediately when no active RND session.
#
# Responsibilities:
#   1. Audit logging (Write/Edit) — appends JSONL to $RND_DIR/audit.jsonl
#   2. Observation mask (Bash) — advises when output exceeds threshold
#
# Always exits 0. Produces advisory JSON or nothing.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Fast-path: skip if no active session
session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0

readonly LINE_THRESHOLD=50

raw="$(cat)"
tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null || true)"

case "$tool_name" in
  Write|Create|write|Edit|edit)
    # Audit logging
    printf '%s' "$raw" | jq -c --arg ts "$(iso_timestamp)" '
      {ts: $ts, tool: (.tool_name // ""), file: (.tool_input.file_path // "")}
      | select(.file != "")' >> "${session_dir}/audit.jsonl" 2>/dev/null || true
    ;;
  Bash|Execute|bash)
    # Observation mask
    line_count="$(printf '%s' "$raw" | jq -r '.stdout // empty' 2>/dev/null | wc -l | tr -d ' ')" || line_count=0
    if [[ "$line_count" -gt "$LINE_THRESHOLD" ]]; then
      advisory_json "Observation mask: Bash output was ${line_count} lines (threshold: ${LINE_THRESHOLD}). Summarize the key signal (pass/fail, errors, counts) in 5-10 lines rather than processing raw output. Verbose observations fill context without proportional value."
    fi
    ;;
esac

exit 0
