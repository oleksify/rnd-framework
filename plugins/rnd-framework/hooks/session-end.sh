#!/usr/bin/env bash
# hooks/session-end.sh — Clears the active RND session on session close/switch.
# Calls rnd-dir.sh --finish to remove .current-session. Always exits 0.
"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --finish 2>/dev/null || true
exit 0
