#!/usr/bin/env bash
# hooks/post-tool-use.sh — PostToolUse hook for Write and Edit.
#
# Audit logging: appends JSONL entry to $RND_DIR/audit.jsonl for any
# Write or Edit tool call during an active session.
#
# Always exits 0. Produces no stdout.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null || true)"
file_path="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"

[[ -n "$file_path" ]] || exit 0

session_dir="$(active_session_dir 2>/dev/null || true)"
if [[ -n "$session_dir" ]]; then
  jq -cn --arg ts "$(iso_timestamp)" --arg tool "$tool_name" --arg file "$file_path" \
    '{ts:$ts,tool:$tool,file:$file}' >> "${session_dir}/audit.jsonl" || true
fi

exit 0
