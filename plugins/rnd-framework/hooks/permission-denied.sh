#!/usr/bin/env bash
# hooks/permission-denied.sh — PermissionDenied hook.
# Fires after auto mode denies a tool permission.
# Emits an advisory suggesting the user add a permission rule or re-run in auto mode.
# Always exits 0 (never blocks, never retries).
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")"

advisory_json "Pipeline permission denied for ${tool_name}. This may interrupt the current pipeline phase. Consider adding a permission rule via /permissions or re-running with auto mode."
exit 0
