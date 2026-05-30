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

# No active pipeline session → no "RND:" title. Omit sessionTitle so Claude Code
# keeps its own auto-generated title; the RND: prefix is for making live pipeline
# sessions findable in /resume, not for branding every prompt in this project.
# active_session_dir only succeeds when the session dir exists on disk, so a
# non-empty session_dir means a genuine live pipeline. Mirrors session-start.sh.
if [[ -z "$session_dir" ]]; then
  jq -cn '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:""}}'
  exit 0
fi

phase="$(detect_pipeline_phase "$session_dir")"
project_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

if [[ "$phase" == "Idle" ]]; then
  title="RND: ${project_name}"
else
  title="RND: ${phase} | ${project_name}"
fi

jq -cn --arg t "$title" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",sessionTitle:$t,additionalContext:""}}'
exit 0
