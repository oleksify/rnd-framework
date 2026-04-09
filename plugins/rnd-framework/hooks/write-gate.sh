#!/usr/bin/env bash
# hooks/write-gate.sh — PreToolUse hook for Write and Edit.
# Auto-allows .rnd/ path operations. No opinion for other paths.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_input
file_path="$(extract_file_path "$TOOL_INPUT")"

if [[ -n "$file_path" ]] && is_plugin_artifact_path "$file_path"; then
  allow_json
  exit 0
fi
exit 0
