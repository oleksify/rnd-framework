#!/usr/bin/env bash
# tests/plugin-dir-base-cache.test.sh — Tests for plugin-dir-base.sh cache path fix.
# Covers: local copies exist and are identical, source lines use local path,
#         and both dir scripts work when invoked from a simulated cache path.
# Usage: bash tests/plugin-dir-base-cache.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Criterion 1: plugins/rnd-framework/lib/plugin-dir-base.sh exists and is
#              identical to lib/plugin-dir-base.sh
# ---------------------------------------------------------------------------
printf '%s\n' '--- rnd-framework local copy ---'

CANONICAL="${REPO_ROOT}/../../lib/plugin-dir-base.sh"
RND_COPY="${REPO_ROOT}/lib/plugin-dir-base.sh"
ARTIST_COPY="${REPO_ROOT}/..//lib/plugin-dir-base.sh"

# Check rnd-framework copy exists
if [[ -f "$RND_COPY" ]]; then
  assert_eq "plugins/rnd-framework/lib/plugin-dir-base.sh exists" "yes" "yes"
else
  assert_eq "plugins/rnd-framework/lib/plugin-dir-base.sh exists" "yes" "no"
fi

# Check rnd-framework copy is identical to canonical
if diff -q "$CANONICAL" "$RND_COPY" >/dev/null 2>&1; then
  assert_eq "rnd-framework copy is identical to canonical lib/plugin-dir-base.sh" "identical" "identical"
else
  assert_eq "rnd-framework copy is identical to canonical lib/plugin-dir-base.sh" "identical" "differs"
fi

# ---------------------------------------------------------------------------
# Criterion 2: plugins//lib/plugin-dir-base.sh exists and is
#              identical to lib/plugin-dir-base.sh
# ---------------------------------------------------------------------------
printf '%s\n' '---  local copy ---'

if [[ -f "$ARTIST_COPY" ]]; then
  assert_eq "plugins//lib/plugin-dir-base.sh exists" "yes" "yes"
else
  assert_eq "plugins//lib/plugin-dir-base.sh exists" "yes" "no"
fi

if diff -q "$CANONICAL" "$ARTIST_COPY" >/dev/null 2>&1; then
  assert_eq " copy is identical to canonical lib/plugin-dir-base.sh" "identical" "identical"
else
  assert_eq " copy is identical to canonical lib/plugin-dir-base.sh" "identical" "differs"
fi

# ---------------------------------------------------------------------------
# Criterion 3: rnd-dir.sh sources via ${_SCRIPT_DIR}/plugin-dir-base.sh
# ---------------------------------------------------------------------------
printf '%s\n' '--- rnd-dir.sh source line ---'

RND_DIR_SCRIPT="${REPO_ROOT}/lib/rnd-dir.sh"
if grep -q '\${_SCRIPT_DIR}/plugin-dir-base\.sh' "$RND_DIR_SCRIPT"; then
  assert_eq "rnd-dir.sh uses local source path" "yes" "yes"
else
  assert_eq "rnd-dir.sh uses local source path" "yes" "no"
fi

# Confirm the old traversal path is gone
if grep -q '\.\./\.\./\.\./lib/plugin-dir-base\.sh' "$RND_DIR_SCRIPT"; then
  assert_eq "rnd-dir.sh does not use old relative path" "no" "yes"
else
  assert_eq "rnd-dir.sh does not use old relative path" "no" "no"
fi

# ---------------------------------------------------------------------------
# Criterion 4: rnd-dir.sh sources via ${_SCRIPT_DIR}/plugin-dir-base.sh
# ---------------------------------------------------------------------------
printf '%s\n' '--- rnd-dir.sh source line ---'

ARTIST_DIR_SCRIPT="${REPO_ROOT}/..//lib/rnd-dir.sh"
if grep -q '\${_SCRIPT_DIR}/plugin-dir-base\.sh' "$ARTIST_DIR_SCRIPT"; then
  assert_eq "rnd-dir.sh uses local source path" "yes" "yes"
else
  assert_eq "rnd-dir.sh uses local source path" "yes" "no"
fi

if grep -q '\.\./\.\./\.\./lib/plugin-dir-base\.sh' "$ARTIST_DIR_SCRIPT"; then
  assert_eq "rnd-dir.sh does not use old relative path" "no" "yes"
else
  assert_eq "rnd-dir.sh does not use old relative path" "no" "no"
fi

# ---------------------------------------------------------------------------
# Criteria 5 & 6: Both dir scripts succeed when invoked from a simulated
#                 plugin cache path (no root lib/ directory present).
#
# Simulation: create a temp dir that mimics the cache layout:
#   <tmpdir>/plugins/cache/rnd-framework/lib/rnd-dir.sh
#   <tmpdir>/plugins/cache/rnd-framework/lib/plugin-dir-base.sh
# (no <tmpdir>/lib/ directory — the old path would fail here)
# ---------------------------------------------------------------------------
printf '%s\n' '--- rnd-dir.sh -c from simulated cache path ---'

TMPBASE="$(mktemp -d)"
trap 'rm -rf "$TMPBASE"' EXIT

# Build simulated cache for rnd-framework
CACHE_RND="${TMPBASE}/plugins/cache/rnd-framework/lib"
mkdir -p "$CACHE_RND"
cp "${REPO_ROOT}/lib/rnd-dir.sh"           "$CACHE_RND/rnd-dir.sh"
cp "${REPO_ROOT}/lib/plugin-dir-base.sh"   "$CACHE_RND/plugin-dir-base.sh"

# Run rnd-dir.sh -c from the cache path using a temp config dir
TMPCONFIG="${TMPBASE}/config"
mkdir -p "$TMPCONFIG"

RND_RESULT=""
RND_EXIT=0
RND_RESULT="$(CLAUDE_CONFIG_DIR="$TMPCONFIG" bash "${CACHE_RND}/rnd-dir.sh" -c 2>&1)" || RND_EXIT=$?

assert_eq "rnd-dir.sh -c exits 0 from cache path" "0" "$RND_EXIT"

if [[ -n "$RND_RESULT" && -d "$RND_RESULT" ]]; then
  assert_eq "rnd-dir.sh -c outputs a directory path that exists" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c outputs a directory path that exists" "yes" "no: '$RND_RESULT'"
fi

printf '%s\n' '--- rnd-dir.sh -c from simulated cache path ---'

# Build simulated cache for 
CACHE_ARTIST="${TMPBASE}/plugins/cache//lib"
mkdir -p "$CACHE_ARTIST"
cp "${REPO_ROOT}/..//lib/rnd-dir.sh"  "$CACHE_ARTIST/rnd-dir.sh"
cp "${REPO_ROOT}/..//lib/plugin-dir-base.sh" "$CACHE_ARTIST/plugin-dir-base.sh"

TMPCONFIG_ARTIST="${TMPBASE}/config-"
mkdir -p "$TMPCONFIG_ARTIST"

ARTIST_RESULT=""
ARTIST_EXIT=0
ARTIST_RESULT="$(CLAUDE_CONFIG_DIR="$TMPCONFIG_ARTIST" bash "${CACHE_ARTIST}/rnd-dir.sh" -c 2>&1)" || ARTIST_EXIT=$?

assert_eq "rnd-dir.sh -c exits 0 from cache path" "0" "$ARTIST_EXIT"

if [[ -n "$ARTIST_RESULT" && -d "$ARTIST_RESULT" ]]; then
  assert_eq "rnd-dir.sh -c outputs a directory path that exists" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c outputs a directory path that exists" "yes" "no: '$ARTIST_RESULT'"
fi

report
