#!/usr/bin/env bash
# hooks/stop-failure.sh — Logs StopFailure API errors to $RND_DIR/stop-failures.jsonl.
# Always exits 0. StopFailure events do not have tool_name/tool_input; read stdin directly.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
error_type="$(jq_extract "$raw" '.error_type')"
message="$(jq_extract "$raw" '.message')"
[[ -n "$error_type" ]] || error_type="unknown"
[[ -n "$message" ]] || message="unknown"

rnd_dir="$(active_session_dir 2>/dev/null || true)"
if [[ -n "$rnd_dir" ]]; then
  entry="$(jq -cn --arg ts "$(iso_timestamp)" --arg et "$error_type" --arg msg "$message" \
    '{ts:$ts,errorType:$et,message:$msg}')"
  printf '%s\n' "$entry" >> "${rnd_dir}/stop-failures.jsonl" || true
fi

advisory_json "API error encountered. Wait a moment before retrying, or adjust rate limits if errors persist."
exit 0
