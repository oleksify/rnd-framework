#!/usr/bin/env bash
# hooks/worktree-create.sh — WorktreeCreate hook for rnd-framework plugin.
#
# Contract (Claude Code v2.1.83+):
#   The harness invokes this hook when an agent declares isolation="worktree".
#   stdin  : {session_id, transcript_path, cwd, hook_event_name, name, ...}
#   stdout : the worktree path the harness should create. Required — absence
#            of a path on stdout aborts the agent spawn.
#
# We place worktrees under
#   <cwd>/.rnd-worktrees/<rnd-session-id>/<agent-name>
# so they sit inside the project's git repo (so `git worktree add` works) and
# remain swept by session-end.sh on session close. When no RND session is
# active, the path falls back to <cwd>/.rnd-worktrees/_adhoc/<agent-name>.
#
# Side effect: best-effort audit_event when an RND session is active.

set -euo pipefail

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"

agent_name="$(printf '%s' "$raw" | jq -r '.name // ""' 2>/dev/null || true)"
cwd="$(printf '%s' "$raw" | jq -r '.cwd // ""' 2>/dev/null || true)"

[[ -n "$cwd" ]] || cwd="$(pwd)"
[[ -n "$agent_name" ]] || agent_name="agent-$$"

if [[ -z "${RND_DIR:-}" ]]; then
  RND_DIR="$(active_session_dir 2>/dev/null || true)"
  export RND_DIR
fi

if [[ -n "${RND_DIR:-}" ]]; then
  rnd_session_id="$(basename "$RND_DIR")"
else
  rnd_session_id="_adhoc"
fi

wt_root="${cwd}/.rnd-worktrees/${rnd_session_id}"
wt_path="${wt_root}/${agent_name}"

mkdir -p "$wt_path" 2>/dev/null || true

if [[ -n "${RND_DIR:-}" ]]; then
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  "${plugin_root}/lib/audit-event.sh" worktree_created "$rnd_session_id" "$wt_path" 2>/dev/null || true
fi

printf '%s\n' "$wt_path"
exit 0
