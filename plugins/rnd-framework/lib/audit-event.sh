#!/usr/bin/env bash
# audit-event.sh — Append a single audit event line to $RND_DIR/audit.jsonl.
#
# Usage:
#   audit-event.sh <event> <task_id> <tool>
#
# Single source of truth for audit-event JSON format. Used by run-tool.sh
# (event=tool_run_fresh) and by the Verifier (event=tool_pack_served when
# the evidence pack's input hashes match current source state).
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Event appended (or silently skipped on write failure).
#   1  Missing argument or RND_DIR unset.

set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'Usage: audit-event.sh <event> <task_id> <tool>\n' >&2
  exit 1
fi

event="$1"
task_id="$2"
tool="$3"

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'audit-event.sh: RND_DIR is not set\n' >&2
  exit 1
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -nc \
  --arg event "$event" \
  --arg task_id "$task_id" \
  --arg tool "$tool" \
  --arg ts "$ts" \
  '{event:$event, task_id:$task_id, tool:$tool, timestamp:$ts}' \
  >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
