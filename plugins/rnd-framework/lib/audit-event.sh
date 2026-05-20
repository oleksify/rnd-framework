#!/usr/bin/env bash
# audit-event.sh — Append a single audit event line to $RND_DIR/audit.jsonl.
#
# Usage:
#   audit-event.sh <event> <task_id> <tool> [assertion_id]
#
# task_id accepts both the legacy short form (T<n>, e.g. T1, T12) and the
# stable full form (M<N>.T<NN>.<slug>, e.g. M1.T01.verifier-per-assertion).
#
# Single source of truth for audit-event JSON format. Used by run-tool.sh
# (event=tool_run_fresh) and by the Verifier (event=tool_pack_served when
# the evidence pack's input hashes match current source state).
#
# The optional 4th argument assertion_id, when non-empty, is included in
# the emitted JSON. All existing 3-argument call sites continue to work.
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Event appended (or silently skipped on write failure).
#   1  Missing argument or RND_DIR unset.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  printf 'Usage: audit-event.sh <event> <task_id> <tool> [assertion_id]\n' >&2
  exit 1
fi

event="$1"
task_id="$2"
tool="$3"
assertion_id="${4:-}"

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'audit-event.sh: RND_DIR is not set\n' >&2
  exit 1
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ -n "$assertion_id" ]]; then
  jq -nc \
    --arg event "$event" \
    --arg task_id "$task_id" \
    --arg tool "$tool" \
    --arg ts "$ts" \
    --arg assertion_id "$assertion_id" \
    '{event:$event, task_id:$task_id, tool:$tool, timestamp:$ts, assertion_id:$assertion_id}' \
    >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
else
  jq -nc \
    --arg event "$event" \
    --arg task_id "$task_id" \
    --arg tool "$tool" \
    --arg ts "$ts" \
    '{event:$event, task_id:$task_id, tool:$tool, timestamp:$ts}' \
    >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
fi
