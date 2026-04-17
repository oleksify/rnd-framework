#!/usr/bin/env bash
# hooks/session-title.sh — UserPromptSubmit hook for rnd-framework plugin.
# Sets the session title to reflect the current pipeline phase and project name.
# Output: {hookSpecificOutput:{sessionTitle:"RND: <phase> | <project>"}}
# Always exits 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Advisory hook — must never block prompt submission.
# lib.sh sets -euo pipefail; disable errexit so transient failures
# (stale cache files, slow git, missing jq) degrade to a no-op.
set +e

session_dir="$(active_session_dir 2>/dev/null || true)"
phase="$(detect_pipeline_phase "$session_dir")"

# Extract project name from git root or cwd basename.
project_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

# Compose session title.
if [[ "$phase" == "Idle" ]]; then
  title="RND: ${project_name}"
else
  title="RND: ${phase} | ${project_name}"
fi

jq -cn --arg t "$title" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",sessionTitle:$t,additionalContext:""}}'
exit 0
