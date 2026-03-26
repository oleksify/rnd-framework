#!/usr/bin/env bash
# hooks/glob-grep-gate.sh — PreToolUse hook for Glob and Grep.
# Auto-allows .rnd/ and .rnd/ path operations. No opinion for other paths.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
tool_input="$(jq_extract "$raw" '.tool_input')"

# Glob uses .path, Grep uses .path — extract whichever is present
path="$(jq_extract "$tool_input" '.path')"

if [[ -n "$path" ]] && is_plugin_artifact_path "$path"; then
  allow_json
fi
exit 0
