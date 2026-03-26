#!/usr/bin/env bash
# hooks/post-tool-use.sh — PostToolUse hook for Write and Edit.
#
# Audit logging: appends JSONL entry to $RND_DIR/audit.jsonl for any
# Write or Edit tool call during an active session.
#
# Always exits 0. Produces no stdout.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Short-circuit: skip audit if no active session (avoids all jq work)
session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0

raw="$(cat)"
# Single jq call: extract tool_name and file_path, append audit entry directly
printf '%s' "$raw" | jq -c --arg ts "$(iso_timestamp)" '
  {ts: $ts, tool: (.tool_name // ""), file: (.tool_input.file_path // "")}
  | select(.file != "")' >> "${session_dir}/audit.jsonl" 2>/dev/null || true

exit 0
