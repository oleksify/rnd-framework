#!/usr/bin/env bash
# hooks/cwd-changed.sh — CwdChanged hook for rnd-framework plugin (v2.1.83+).
# Detects when the working directory changes mid-session and warns if
# the active RND session was created for a different project directory.
#
# Exits 0 with advisory context if a mismatch is detected, or silently if not.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Read the new cwd from hook input
raw="$(cat)"
new_cwd="$(printf '%s' "$raw" | jq -r '.cwd // ""' 2>/dev/null || true)"

# If we can't determine the new cwd, exit silently
[[ -n "$new_cwd" ]] || exit 0

# Check if there's an active session
session_dir="$(active_session_dir)" || exit 0

# The session dir encodes the project hash. If the new cwd would produce
# a different base dir, the session is stale for this directory.
current_base="$(resolve_rnd_dir --base)" || exit 0
new_base_candidate="$new_cwd"

# Simple check: if the new cwd is outside the git repo that the session
# was created for, emit a warning.
git_root="$(cd "$new_cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
session_git_root="$(cd "$(dirname "$session_dir")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -n "$git_root" && -n "$session_git_root" && "$git_root" != "$session_git_root" ]]; then
  advisory_json "Working directory changed to a different repository (\`$new_cwd\`). The active RND session was created for \`$session_git_root\`. Pipeline artifacts may reference the wrong project."
  exit 0
fi

exit 0
