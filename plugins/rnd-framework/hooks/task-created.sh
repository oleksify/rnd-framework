#!/usr/bin/env bash
# hooks/task-created.sh — TaskCreated hook.
#
# Audit logging: appends JSONL entry to $RND_DIR/audit.jsonl for any
# task creation event during an active session.
#
# Always exits 0. Produces no stdout.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Short-circuit: skip audit if no active session
session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0

raw="$(cat)"
# Single jq call: extract fields and build audit entry directly
printf '%s' "$raw" | jq -c --arg ts "$(iso_timestamp)" '
  {ts: $ts, event: "task_created",
   task_id: (.task_id // ""), task_description: (.task_description // "")}' \
  >> "${session_dir}/audit.jsonl" 2>/dev/null || true

exit 0
