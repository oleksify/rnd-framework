#!/usr/bin/env bash
# hooks/write-gate.sh — PreToolUse hook for Write and Edit.
# Auto-allows .rnd/ path operations. No opinion for other paths.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
file_path="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"

if is_rnd_path "$file_path"; then
  allow_json
fi
exit 0
