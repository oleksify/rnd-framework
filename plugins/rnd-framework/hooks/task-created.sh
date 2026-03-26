#!/usr/bin/env bash
# hooks/task-created.sh — TaskCreated hook.
#
# Audit logging: appends JSONL entry to $RND_DIR/audit.jsonl for any
# task creation event during an active session.
#
# Always exits 0. Produces no stdout.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
task_id="$(jq_extract "$raw" '.task_id')"
task_description="$(jq_extract "$raw" '.task_description')"

session_dir="$(active_session_dir 2>/dev/null || true)"
if [[ -n "$session_dir" ]]; then
  jq -cn --arg ts "$(iso_timestamp)" --arg id "$task_id" --arg desc "$task_description" \
    '{ts:$ts,event:"task_created",task_id:$id,task_description:$desc}' >> "${session_dir}/audit.jsonl" || true
fi

exit 0
