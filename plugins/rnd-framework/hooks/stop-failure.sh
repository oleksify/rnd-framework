#!/usr/bin/env bash
# hooks/stop-failure.sh — Logs StopFailure API errors to $RND_DIR/stop-failures.jsonl.
# Always exits 0. StopFailure events do not have tool_name/tool_input; read stdin directly.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"

rnd_dir="$(active_session_dir 2>/dev/null || true)"
if [[ -n "$rnd_dir" ]]; then
  # Single jq call: extract fields and build log entry directly
  printf '%s' "$raw" | jq -c --arg ts "$(iso_timestamp)" '
    {ts: $ts, errorType: (.error_type // "unknown"), message: (.message // "unknown")}' \
    >> "${rnd_dir}/stop-failures.jsonl" 2>/dev/null || true
fi

advisory_json "API error encountered. Wait a moment before retrying, or adjust rate limits if errors persist."
exit 0
