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
# Criterion 2: rnd-dir.sh sources via ${_SCRIPT_DIR}/plugin-dir-base.sh
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
# Criterion 3: rnd-dir.sh succeeds when invoked from a simulated
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

# ---------------------------------------------------------------------------
# Regression: no platform env vars set — must default to $HOME/.claude
# ---------------------------------------------------------------------------
printf '%s\n' '--- Default: no platform env vars ---'

FAKEHOME3="${TMPBASE}/fakehome3"
mkdir -p "$FAKEHOME3"

RND_DEFAULT_RESULT=""
RND_DEFAULT_EXIT=0
RND_DEFAULT_RESULT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT HOME="$FAKEHOME3" bash "${CACHE_RND}/rnd-dir.sh" -c 2>&1)" || RND_DEFAULT_EXIT=$?

assert_eq "rnd-dir.sh -c with no platform vars exits 0" "0" "$RND_DEFAULT_EXIT"

if [[ "$RND_DEFAULT_RESULT" == "${FAKEHOME3}/.claude/"* ]]; then
  assert_eq "rnd-dir.sh -c defaults to \$HOME/.claude" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c defaults to \$HOME/.claude" "yes" "no: '$RND_DEFAULT_RESULT'"
fi

# ---------------------------------------------------------------------------
# Criterion 5: No .active-base-dir write inside _plugin_dir_create_session in
#              either copy.
# ---------------------------------------------------------------------------
printf '%s\n' '--- .active-base-dir write removed from _plugin_dir_create_session ---'

for _copy_label in "canonical:${CANONICAL}" "rnd-framework:${RND_COPY}"; do
  _label="${_copy_label%%:*}"
  _path="${_copy_label#*:}"
  if [[ -f "$_path" ]] && grep -q 'active-base-dir' "$_path"; then
    assert_eq "${_label}: no .active-base-dir write in _plugin_dir_create_session" "absent" "present"
  else
    assert_eq "${_label}: no .active-base-dir write in _plugin_dir_create_session" "absent" "absent"
  fi
done

# ---------------------------------------------------------------------------
# Criterion 7: Mutation guard — test fails if either copy drifts.
# Simulates a drift by introducing a comment into a temp copy, then checks
# that a diff would catch it (exercises the diff logic used above).
# ---------------------------------------------------------------------------
printf '%s\n' '--- mutation guard: single copy drift is caught ---'

MUTATED_DIR="$(mktemp -d)"
trap 'rm -rf "$MUTATED_DIR"; rm -rf "$TMPBASE"' EXIT

cp "$CANONICAL" "${MUTATED_DIR}/canonical.sh"
cp "$RND_COPY"  "${MUTATED_DIR}/rnd-framework.sh"

# Introduce drift into one copy
printf '\n# drift\n' >> "${MUTATED_DIR}/rnd-framework.sh"

_drift_detected=no
if ! diff -q "${MUTATED_DIR}/canonical.sh" "${MUTATED_DIR}/rnd-framework.sh" >/dev/null 2>&1; then
  _drift_detected=yes
fi

assert_eq "mutation guard detects drift in any copy" "yes" "$_drift_detected"

report
