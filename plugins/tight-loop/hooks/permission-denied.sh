#!/usr/bin/env bash
# hooks/permission-denied.sh — PermissionDenied hook (v2.1.89+).
# Fires after auto mode classifier denies a tool permission.
# Logs the denial to audit.jsonl and returns {retry: true} so the model can retry.
# Always exits 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // "unknown"' 2>/dev/null || printf '%s' "unknown")"

# ---------------------------------------------------------------------------
# Audit log — append to audit.jsonl in tight-loop base dir
# ---------------------------------------------------------------------------

base_dir="$(tight_base_dir)" || true
if [[ -n "$base_dir" ]]; then
  ts="$(iso_timestamp)"
  jq -cn \
    --arg ts "$ts" \
    --arg tool "$tool_name" \
    --arg event "permission_denied" \
    '{timestamp:$ts, event:$event, tool:$tool}' \
    >> "${base_dir}/audit.jsonl" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Response — tell the model it can retry the tool call
# ---------------------------------------------------------------------------

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionDenied","retry":true}}'
exit 0
