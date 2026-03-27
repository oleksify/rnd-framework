#!/usr/bin/env bash
# hooks/glob-grep-gate.sh — PreToolUse hook for Glob and Grep.
# Auto-allows .rnd/ and .rnd/ path operations. No opinion for other paths.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_input
path="$(printf '%s' "$TOOL_INPUT" | jq -r '.path // ""' 2>/dev/null || true)"

if [[ -n "$path" ]] && is_plugin_artifact_path "$path"; then
  allow_json
  exit 0
fi
exit 0
