#!/usr/bin/env bash
# hooks/worktree-remove.sh — WorktreeRemove hook for rnd-framework plugin.
# Records a worktree_removed event to $RND_DIR/audit.jsonl. Always exits 0.

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"
wt_path="$(printf '%s' "$raw" | jq -r '(.tool_input.path // .tool_input.worktree_path // .tool_input.worktreePath // .path // .worktree_path // .worktreePath // "")' 2>/dev/null || true)"
[[ -n "$wt_path" ]] || wt_path="<unknown>"

if [[ -z "${RND_DIR:-}" ]]; then
  RND_DIR="$(active_session_dir 2>/dev/null || true)"
  export RND_DIR
fi
[[ -n "${RND_DIR:-}" ]] || exit 0

session_id="$(basename "$RND_DIR")"
plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${plugin_root}/lib/audit-event.sh" worktree_removed "$session_id" "$wt_path" 2>/dev/null || true

exit 0
