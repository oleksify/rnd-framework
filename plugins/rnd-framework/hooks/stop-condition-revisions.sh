#!/usr/bin/env bash
# hooks/stop-condition-revisions.sh — PreToolUse Write|Edit hook.
# Blocks a Write or Edit when the same file has been written/edited
# more than RND_STOP_FILE_REVISIONS times in the active session.
#
# Exits 0 (no-opinion) when no active session, threshold not reached,
# or the env var is unset (default 5).
# Exits 2 (block) when the count reaches the threshold.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

# Fast-path: skip if no active session
session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0

# Validate and resolve threshold
readonly DEFAULT_THRESHOLD=5
threshold="${RND_STOP_FILE_REVISIONS:-$DEFAULT_THRESHOLD}"

if ! printf '%s' "$threshold" | grep -qE '^[0-9]+$'; then
  printf 'stop-condition-revisions: RND_STOP_FILE_REVISIONS must be a non-negative integer, got: %s\n' "$threshold" >&2
  exit 2
fi

# Parse stdin — read once, extract file_path
raw="$(cat)"
file_path="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"

[[ -n "$file_path" ]] || exit 0

# Resolve active task_id from the most recent build manifest filename.
# Falls back to empty string when no manifest exists (tolerated by audit-scan.sh).
task_id=""
if compgen -G "${session_dir}/builds/T*-manifest.md" > /dev/null 2>&1; then
  latest_manifest="$(ls -t "${session_dir}/builds/"T*-manifest.md 2>/dev/null | head -n1 || true)"
  if [[ -n "$latest_manifest" ]]; then
    manifest_base="${latest_manifest##*/}"
    task_id="${manifest_base%-manifest.md}"
  fi
fi

# Count revisions via audit-scan.sh
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
audit_scan="${script_dir}/../lib/audit-scan.sh"

count=0
if [[ -x "$audit_scan" ]]; then
  count="$(RND_DIR="$session_dir" "$audit_scan" revisions "${task_id:-unknown}" "$file_path" 2>/dev/null || true)"
  count="${count:-0}"
fi

# Block when count reaches threshold
if [[ "$count" -ge "$threshold" ]]; then
  # Emit gateFired audit event
  audit_event="${script_dir}/../lib/audit-event.sh"
  if [[ -x "$audit_event" ]]; then
    RND_DIR="$session_dir" "$audit_event" \
      "gate_fired" \
      "${task_id:-unknown}" \
      "stop_condition_revisions" 2>/dev/null || true
  fi

  block_msg "STOP CONDITION: file '${file_path}' has been written/edited ${count} time(s) in task ${task_id:-unknown} (threshold RND_STOP_FILE_REVISIONS=${threshold}).

Pipeline halted to prevent runaway revisions to the same file.

Options:
  1. Override threshold: set RND_STOP_FILE_REVISIONS=<N> to a higher value.
  2. Review the file's revision history in the audit log: ${session_dir}/audit.jsonl
  3. Consider whether the design needs rethinking if this many revisions were needed."
fi

exit 0
