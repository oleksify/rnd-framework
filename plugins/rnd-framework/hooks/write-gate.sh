#!/usr/bin/env bash
# hooks/write-gate.sh — PreToolUse hook for Write and Edit.
# Blocks /tmp/ writes. Auto-allows .rnd/ path operations. No opinion for other paths.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
file_path="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"

if [[ "$file_path" == /tmp/* ]]; then
  block_msg "BLOCKED: Do not write to /tmp/. Use \$RND_DIR for temporary files — it is auto-allowed and preserves artifacts across the pipeline session."
fi

if is_plugin_artifact_path "$file_path"; then
  allow_json
  exit 0
fi
exit 0
