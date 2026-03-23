#!/usr/bin/env bash
# tests/session-end.test.sh — Tests for hooks/session-end.sh
# Usage: bash tests/session-end.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/session-end.sh"
RND_DIR_SH="${SCRIPT_DIR}/../lib/rnd-dir.sh"

PASS=0
FAIL=0

pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# session-end.sh requires CLAUDE_PLUGIN_ROOT to resolve rnd-dir.sh.
# Build a temporary plugin root pointing at our actual hooks/lib dir.
# ---------------------------------------------------------------------------

tmp_plugin="$(mktemp -d)"
mkdir -p "${tmp_plugin}/lib"
# Symlink the real rnd-dir.sh into our fake plugin root
ln -sf "${RND_DIR_SH}" "${tmp_plugin}/lib/rnd-dir.sh"

# Create a fake config dir with an active session
tmp_config="$(mktemp -d)"
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" CLAUDE_PLUGIN_ROOT="$tmp_plugin" "$RND_DIR_SH" --base 2>/dev/null || true)"

cleanup() {
  rm -rf "$tmp_plugin" "$tmp_config"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Test: always exits 0
# ---------------------------------------------------------------------------

HOOK_EXIT=0
CLAUDE_PLUGIN_ROOT="$tmp_plugin" "$HOOK" >/dev/null 2>/dev/null || HOOK_EXIT=$?
if [[ "$HOOK_EXIT" -eq 0 ]]; then
  pass "session-end.sh always exits 0 (no active session)"
else
  fail "session-end.sh always exits 0 (no active session)" "got $HOOK_EXIT"
fi

# ---------------------------------------------------------------------------
# Test: clears .current-session when one exists
# ---------------------------------------------------------------------------

if [[ -n "$base_dir" ]]; then
  mkdir -p "$base_dir"
  session_id="20260101-120000-abcd"
  printf '%s' "$session_id" > "${base_dir}/.current-session"

  if [[ -f "${base_dir}/.current-session" ]]; then
    pass ".current-session file created for test"
  else
    fail ".current-session file created for test" "file not found"
  fi

  HOOK_EXIT=0
  CLAUDE_CONFIG_DIR="$tmp_config" CLAUDE_PLUGIN_ROOT="$tmp_plugin" "$HOOK" >/dev/null 2>/dev/null || HOOK_EXIT=$?

  if [[ "$HOOK_EXIT" -eq 0 ]]; then
    pass "session-end.sh exits 0 when clearing active session"
  else
    fail "session-end.sh exits 0 when clearing active session" "got $HOOK_EXIT"
  fi

  if [[ ! -f "${base_dir}/.current-session" ]]; then
    pass ".current-session file is removed after session-end"
  else
    fail ".current-session file is removed after session-end" "file still exists"
  fi

  # Idempotent: running again with no session file still exits 0
  HOOK_EXIT=0
  CLAUDE_CONFIG_DIR="$tmp_config" CLAUDE_PLUGIN_ROOT="$tmp_plugin" "$HOOK" >/dev/null 2>/dev/null || HOOK_EXIT=$?
  if [[ "$HOOK_EXIT" -eq 0 ]]; then
    pass "session-end.sh is idempotent (exits 0 when no .current-session)"
  else
    fail "session-end.sh is idempotent (exits 0 when no .current-session)" "got $HOOK_EXIT"
  fi
else
  fail "base_dir resolved from rnd-dir.sh" "(rnd-dir.sh failed; skipping session-clear tests)"
  fail "session-end.sh exits 0 when clearing active session" "(skipped)"
  fail ".current-session file is removed after session-end" "(skipped)"
  fail "session-end.sh is idempotent" "(skipped)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
