#!/usr/bin/env bash
# hooks/session-end.sh — Clears the active RND session on session close/switch.
# Calls rnd-dir.sh --finish to remove .current-session. Sweeps any orphaned
# rnd-owned worktrees (paths under .rnd-worktrees/) so they don't leak across
# pipeline runs. Always exits 0; sweep failures never block shutdown.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

resolve_rnd_dir --finish 2>/dev/null || true

if git rev-parse --git-dir >/dev/null 2>&1; then
  orphans="$(git worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / && /\.rnd-worktrees\// { print $2 }' || true)"
  while IFS= read -r wt; do
    [[ -n "$wt" ]] && git worktree remove --force "$wt" 2>/dev/null || true
  done <<< "$orphans"
fi

exit 0
