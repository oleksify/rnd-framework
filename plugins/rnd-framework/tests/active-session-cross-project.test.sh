#!/usr/bin/env bash
# tests/active-session-cross-project.test.sh
# Regression test for the cross-project contamination bug in
# hooks/lib.sh::active_session_dir. The .active-base-dir fast-path cache is a
# SINGLE file shared by every project under one config dir; a concurrent or
# prior session in a DIFFERENT project can leave a foreign base-dir pointer
# there. active_session_dir must validate ownership (cwd git root vs the base
# dir's recorded .session-git-root) before trusting the cache.
#
# Revert-proof: with the ownership check removed, case 1 returns the FOREIGN
# session dir (the original bug) and fails this test.
#
# Usage: bash tests/active-session-cross-project.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

LIB="${SCRIPT_DIR}/../hooks/lib.sh"

if ! command -v git >/dev/null 2>&1; then
  printf 'SKIP: git not available\n'
  exit 0
fi

CONFIG_DIR="$(mktemp -d)"
CUR_REPO="$(mktemp -d)"
trap 'rm -rf "$CONFIG_DIR" "$CUR_REPO"' EXIT

git -C "$CUR_REPO" init -q
CUR_TOP="$(cd "$CUR_REPO" && git rev-parse --show-toplevel)"

mkdir -p "${CONFIG_DIR}/.rnd"

# Resolve active_session_dir from inside CUR_REPO in a FRESH process each time
# (avoids the process-level memo in active_session_dir).
resolve_from_cur_repo() {
  ( cd "$CUR_REPO" \
      && CLAUDE_CONFIG_DIR="$CONFIG_DIR" HOME="$CONFIG_DIR" \
         bash -c "source '$LIB'; active_session_dir 2>/dev/null || true" )
}

# ---------------------------------------------------------------------------
# Case 1: foreign cache (different .session-git-root) is NOT trusted
# ---------------------------------------------------------------------------
printf '%s\n' '--- active-session cross-project: foreign cache rejected ---'

FOREIGN_BASE="${CONFIG_DIR}/.rnd/foreign-slug/branches/main"
FOREIGN_SESSION="${FOREIGN_BASE}/sessions/20260101-120000-aaaa"
mkdir -p "$FOREIGN_SESSION"
printf '20260101-120000-aaaa' > "${FOREIGN_BASE}/.current-session"
printf '/some/other/project'  > "${FOREIGN_BASE}/.session-git-root"
printf '%s' "$FOREIGN_BASE"   > "${CONFIG_DIR}/.rnd/.active-base-dir"

result="$(resolve_from_cur_repo)"
assert_eq "foreign cache NOT returned for current project" \
  "1" "$([[ "$result" != "$FOREIGN_SESSION" ]] && echo 1 || echo 0)"

# ---------------------------------------------------------------------------
# Case 2: owned cache (.session-git-root == cwd git root) IS trusted
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- active-session cross-project: owned cache trusted ---'

OWN_BASE="${CONFIG_DIR}/.rnd/own-slug/branches/main"
OWN_SESSION="${OWN_BASE}/sessions/20260202-120000-bbbb"
mkdir -p "$OWN_SESSION"
printf '20260202-120000-bbbb' > "${OWN_BASE}/.current-session"
printf '%s' "$CUR_TOP"        > "${OWN_BASE}/.session-git-root"
printf '%s' "$OWN_BASE"       > "${CONFIG_DIR}/.rnd/.active-base-dir"

result="$(resolve_from_cur_repo)"
assert_eq "owned cache returned" "$OWN_SESSION" "$result"

# ---------------------------------------------------------------------------
# Case 3: missing .session-git-root → cache trusted (legacy back-compat)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- active-session cross-project: missing git-root → back-compat trust ---'

rm -f "${OWN_BASE}/.session-git-root"
result="$(resolve_from_cur_repo)"
assert_eq "no .session-git-root → cache still trusted" "$OWN_SESSION" "$result"

# ---------------------------------------------------------------------------
report
