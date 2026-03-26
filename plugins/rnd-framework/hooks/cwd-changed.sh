#!/usr/bin/env bash
# hooks/cwd-changed.sh — CwdChanged hook for rnd-framework plugin (v2.1.83+).
# Detects when the working directory changes mid-session and warns if
# the active RND session was created for a different project directory.
#
# Exits 0 with advisory context if a mismatch is detected, or silently if not.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Read the new cwd from hook input
raw="$(cat)"
new_cwd="$(jq_extract "$raw" '.cwd')"

# If we can't determine the new cwd, exit silently
guard_nonempty "$new_cwd" || exit 0

# Check if there's an active session
session_dir="$(active_session_dir)" || exit 0

# Derive the base dir (parent of sessions/) from the active session dir path.
# session_dir ends with /sessions/<session-id>, so strip two path components.
base_dir="$(dirname "$(dirname "$session_dir")")"

# Read the git root stored by session-start.sh when this session was created.
# The file is absent for non-git projects or sessions predating this feature —
# in both cases exit silently rather than emitting a spurious warning.
session_git_root_file="${base_dir}/.session-git-root"
session_git_root=""
if [[ -f "$session_git_root_file" ]]; then
  session_git_root="$(< "$session_git_root_file")"
fi
[[ -n "$session_git_root" ]] || exit 0

# Resolve the git root for the new working directory.
git_root="$(cd "$new_cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -n "$git_root" && "$git_root" != "$session_git_root" ]]; then
  advisory_json "Working directory changed to a different repository (\`$new_cwd\`). The active RND session was created for \`$session_git_root\`. Pipeline artifacts may reference the wrong project."
  exit 0
fi

exit 0
