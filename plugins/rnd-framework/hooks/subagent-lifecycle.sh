#!/usr/bin/env bash
# hooks/subagent-lifecycle.sh — SubagentStart/SubagentStop hook.
# Logs agent lifecycle events to $RND_DIR/audit.jsonl for pipeline observability.
# Always exits 0 with no stdout (no-opinion).
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

rnd_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$rnd_dir" ]] || exit 0

raw="$(cat)"
event="$(printf '%s' "$raw" | jq -r '.hook_event_name // ""' 2>/dev/null || true)"
agent_id="$(printf '%s' "$raw" | jq -r '.agent_id // ""' 2>/dev/null || true)"
agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

[[ -n "$event" ]] || exit 0

jq -cn \
  --arg event "$event" \
  --arg agent_id "$agent_id" \
  --arg agent_type "$agent_type" \
  --arg ts "$(iso_timestamp)" \
  '{event: $event, agent_id: $agent_id, agent_type: $agent_type, timestamp: $ts}' \
  >> "${rnd_dir}/audit.jsonl" 2>/dev/null || true

exit 0
