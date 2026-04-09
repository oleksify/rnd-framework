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

# Pipeline phase names (constants — mirrors statusline.sh)
readonly PHASE_IDLE="Idle"
readonly PHASE_PLANNING="Planning"
readonly PHASE_BUILDING="Building"
readonly PHASE_VERIFYING="Verifying"
readonly PHASE_INTEGRATING="Integrating"

# Detect pipeline phase by checking session directories.
phase="$PHASE_IDLE"
session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -n "$session_dir" ]]; then
  if compgen -G "${session_dir}/integration/"*.md > /dev/null 2>&1; then
    phase="$PHASE_INTEGRATING"
  elif compgen -G "${session_dir}/verifications/"*.md > /dev/null 2>&1; then
    phase="$PHASE_VERIFYING"
  elif compgen -G "${session_dir}/builds/"*.md > /dev/null 2>&1; then
    phase="$PHASE_BUILDING"
  elif [[ -f "${session_dir}/plan.md" ]]; then
    phase="$PHASE_PLANNING"
  fi
fi

# Extract project name from git root or cwd basename.
project_name="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

# Compose session title.
if [[ "$phase" == "$PHASE_IDLE" ]]; then
  title="RND: ${project_name}"
else
  title="RND: ${phase} | ${project_name}"
fi

jq -cn --arg t "$title" '{hookSpecificOutput:{sessionTitle:$t}}'
exit 0
