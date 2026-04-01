#!/usr/bin/env bash
# hooks/permission-denied.sh — PermissionDenied hook (v2.1.89+).
# Fires after auto mode classifier denies a tool permission.
# Logs the denial to audit.jsonl and returns {retry: true} so the model can retry.
# Always exits 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")"

# ---------------------------------------------------------------------------
# Audit log — append to $RND_DIR/audit.jsonl if an active session exists
# ---------------------------------------------------------------------------

rnd_dir="$(active_session_dir)" || true
if [[ -n "$rnd_dir" ]]; then
  ts="$(iso_timestamp)"
  jq -cn \
    --arg ts "$ts" \
    --arg tool "$tool_name" \
    --arg event "permission_denied" \
    '{timestamp:$ts, event:$event, tool:$tool}' \
    >> "${rnd_dir}/audit.jsonl" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Response — tell the model it can retry the tool call
# ---------------------------------------------------------------------------

printf '%s\n' '{"hookSpecificOutput":{"retry":true}}'
exit 0
