#!/usr/bin/env bash
# hooks/file-changed.sh — FileChanged hook for rnd-framework plugin (v2.1.83+).
# Detects when pipeline artifact files are modified externally and emits
# advisory context so the orchestrator is aware.
#
# Exits 0 with advisory context if a relevant file changed, or silently if not.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

main() {
  local -r PLAN_FILE="plan.md"
  local -r ITERATION_LOG_FILE="iteration-log.md"

  # Read the changed file path from hook input
  local raw
  raw="$(cat)"
  local file_path
  file_path="$(jq_extract "$raw" '.file_path')"

  # If we can't determine the file, exit silently
  guard_nonempty "$file_path" || exit 0

  # Only care about files in the .rnd/ artifact directory
  is_rnd_path "$file_path" || exit 0

  # Determine which artifact was modified
  local basename
  basename="$(basename "$file_path")"
  case "$basename" in
    "$PLAN_FILE")
      advisory_json "RND plan file was modified externally (\`$file_path\`). Re-read the plan before continuing."
      ;;
    "$ITERATION_LOG_FILE")
      advisory_json "RND iteration log was modified externally (\`$file_path\`). Check for new iteration entries."
      ;;
    *)
      # For other .rnd/ files, emit a generic advisory
      advisory_json "RND artifact modified externally: \`$basename\`"
      ;;
  esac

  exit 0
}

main
