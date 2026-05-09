#!/usr/bin/env bash
# hooks/prereg-gate.sh — PreToolUse Write|Edit|MultiEdit hook.
#
# Enforces the pre-registration discipline: project files must not be edited
# until the agent has written a prereg-<task-slug>.md file in the base dir.
#
# Algorithm:
#   1. Auto-allow writes to .tight-loop/ artifact paths
#   2. Glob for prereg-*.md in base dir — allow if any found
#   3. Block with instructive message if none found
#
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_input

file_path="$(extract_file_path "$TOOL_INPUT")"

# Only fires on Edit/Write/MultiEdit per hooks.json matcher; defensive check.
case "$TOOL_NAME" in
  Edit|Write|MultiEdit) ;;
  *) allow_json; exit 0 ;;
esac

# Auto-allow writes to the plugin artifact directory.
if is_plugin_artifact_path "$file_path"; then
  allow_json
  exit 0
fi

# Require a prereg-*.md file in the base dir.
base="$(tight_base_dir 2>/dev/null || true)"

if [[ -z "$base" ]]; then
  # Cannot determine base dir — allow rather than block valid work.
  allow_json
  exit 0
fi

shopt -s nullglob
prereg_files=("$base"/prereg-*.md)
shopt -u nullglob

if (( ${#prereg_files[@]} == 0 )); then
  block_msg "tight-loop: no pre-registration found in ${base}. Write ${base}/prereg-<task-slug>.md before editing project files."
fi

allow_json
exit 0
