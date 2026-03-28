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

# ---------------------------------------------------------------------------
# Factory Droid platform detection: DROID_CONFIG_DIR overrides default.
#
# When DROID_CONFIG_DIR is set (and no Claude env vars), rnd-dir.sh -c must
# produce a path under that directory.
# ---------------------------------------------------------------------------
printf '%s\n' '--- Factory Droid: DROID_CONFIG_DIR ---'

TMPFACTORY="${TMPBASE}/factory"
mkdir -p "$TMPFACTORY"

RND_DROID_RESULT=""
RND_DROID_EXIT=0
# Unset Claude vars to isolate Factory Droid env
RND_DROID_RESULT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT DROID_CONFIG_DIR="$TMPFACTORY" bash "${CACHE_RND}/rnd-dir.sh" -c 2>&1)" || RND_DROID_EXIT=$?

assert_eq "rnd-dir.sh -c with DROID_CONFIG_DIR exits 0" "0" "$RND_DROID_EXIT"

if [[ "$RND_DROID_RESULT" == "${TMPFACTORY}"/* ]]; then
  assert_eq "rnd-dir.sh -c path is under DROID_CONFIG_DIR" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c path is under DROID_CONFIG_DIR" "yes" "no: '$RND_DROID_RESULT'"
fi

ARTIST_DROID_RESULT=""
ARTIST_DROID_EXIT=0
# Unset Claude vars to isolate Factory Droid env
ARTIST_DROID_RESULT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT DROID_CONFIG_DIR="$TMPFACTORY" bash "${CACHE_ARTIST}/rnd-dir.sh" -c 2>&1)" || ARTIST_DROID_EXIT=$?

assert_eq "rnd-dir.sh -c with DROID_CONFIG_DIR exits 0" "0" "$ARTIST_DROID_EXIT"

if [[ "$ARTIST_DROID_RESULT" == "${TMPFACTORY}"/* ]]; then
  assert_eq "rnd-dir.sh -c path is under DROID_CONFIG_DIR" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c path is under DROID_CONFIG_DIR" "yes" "no: '$ARTIST_DROID_RESULT'"
fi

# ---------------------------------------------------------------------------
# Factory Droid platform detection: DROID_PLUGIN_ROOT (no config dir set)
# must fall back to $HOME/.factory as the config directory.
# ---------------------------------------------------------------------------
printf '%s\n' '--- Factory Droid: DROID_PLUGIN_ROOT fallback ---'

FAKEHOME="${TMPBASE}/fakehome"
mkdir -p "$FAKEHOME"

RND_DROID2_RESULT=""
RND_DROID2_EXIT=0
# Unset Claude vars; set a controlled HOME so we can verify ~/.factory path
RND_DROID2_RESULT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT HOME="$FAKEHOME" DROID_PLUGIN_ROOT="/droid/plugins/cache/x" bash "${CACHE_RND}/rnd-dir.sh" -c 2>&1)" || RND_DROID2_EXIT=$?

assert_eq "rnd-dir.sh -c with DROID_PLUGIN_ROOT exits 0" "0" "$RND_DROID2_EXIT"

if [[ "$RND_DROID2_RESULT" == "${FAKEHOME}/.factory/"* ]]; then
  assert_eq "rnd-dir.sh -c path uses \$HOME/.factory fallback" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c path uses \$HOME/.factory fallback" "yes" "no: '$RND_DROID2_RESULT'"
fi

# ---------------------------------------------------------------------------
# OpenCode platform detection: OPENCODE_CONFIG_DIR (no Claude/Droid vars)
# must use OPENCODE_CONFIG_DIR as the config directory.
# ---------------------------------------------------------------------------
printf '%s\n' '--- OpenCode: OPENCODE_CONFIG_DIR ---'

TMPOPENCODE="${TMPBASE}/opencode-config"
mkdir -p "$TMPOPENCODE"

RND_OPENCODE_RESULT=""
RND_OPENCODE_EXIT=0
# Unset Claude and Droid vars to isolate OpenCode env
RND_OPENCODE_RESULT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT -u DROID_CONFIG_DIR -u DROID_PLUGIN_ROOT OPENCODE_CONFIG_DIR="$TMPOPENCODE" bash "${CACHE_RND}/rnd-dir.sh" -c 2>&1)" || RND_OPENCODE_EXIT=$?

assert_eq "rnd-dir.sh -c with OPENCODE_CONFIG_DIR exits 0" "0" "$RND_OPENCODE_EXIT"

if [[ "$RND_OPENCODE_RESULT" == "${TMPOPENCODE}"/* ]]; then
  assert_eq "rnd-dir.sh -c path is under OPENCODE_CONFIG_DIR" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c path is under OPENCODE_CONFIG_DIR" "yes" "no: '$RND_OPENCODE_RESULT'"
fi

ARTIST_OPENCODE_RESULT=""
ARTIST_OPENCODE_EXIT=0
ARTIST_OPENCODE_RESULT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT -u DROID_CONFIG_DIR -u DROID_PLUGIN_ROOT OPENCODE_CONFIG_DIR="$TMPOPENCODE" bash "${CACHE_ARTIST}/rnd-dir.sh" -c 2>&1)" || ARTIST_OPENCODE_EXIT=$?

assert_eq "rnd-dir.sh -c with OPENCODE_CONFIG_DIR exits 0" "0" "$ARTIST_OPENCODE_EXIT"

if [[ "$ARTIST_OPENCODE_RESULT" == "${TMPOPENCODE}"/* ]]; then
  assert_eq "rnd-dir.sh -c path is under OPENCODE_CONFIG_DIR" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c path is under OPENCODE_CONFIG_DIR" "yes" "no: '$ARTIST_OPENCODE_RESULT'"
fi

# ---------------------------------------------------------------------------
# OpenCode platform detection: OPENCODE_CONFIG (no OPENCODE_CONFIG_DIR set)
# must fall back to $HOME/.config/opencode as the config directory.
# ---------------------------------------------------------------------------
printf '%s\n' '--- OpenCode: OPENCODE_CONFIG fallback ---'

FAKEHOME2="${TMPBASE}/fakehome2"
mkdir -p "$FAKEHOME2"

RND_OPENCODE2_RESULT=""
RND_OPENCODE2_EXIT=0
# Unset Claude/Droid/OPENCODE_CONFIG_DIR vars; set a controlled HOME
RND_OPENCODE2_RESULT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT -u DROID_CONFIG_DIR -u DROID_PLUGIN_ROOT -u OPENCODE_CONFIG_DIR HOME="$FAKEHOME2" OPENCODE_CONFIG="somevalue" bash "${CACHE_RND}/rnd-dir.sh" -c 2>&1)" || RND_OPENCODE2_EXIT=$?

assert_eq "rnd-dir.sh -c with OPENCODE_CONFIG exits 0" "0" "$RND_OPENCODE2_EXIT"

if [[ "$RND_OPENCODE2_RESULT" == "${FAKEHOME2}/.config/opencode/"* ]]; then
  assert_eq "rnd-dir.sh -c path uses \$HOME/.config/opencode fallback" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c path uses \$HOME/.config/opencode fallback" "yes" "no: '$RND_OPENCODE2_RESULT'"
fi

# ---------------------------------------------------------------------------
# Precedence: CLAUDE_CONFIG_DIR takes priority over OPENCODE_CONFIG_DIR.
# ---------------------------------------------------------------------------
printf '%s\n' '--- OpenCode: CLAUDE_CONFIG_DIR precedence ---'

TMPCLAUDECONFIG="${TMPBASE}/claude-wins"
mkdir -p "$TMPCLAUDECONFIG"

RND_PREC_RESULT=""
RND_PREC_EXIT=0
RND_PREC_RESULT="$(env -u CLAUDE_PLUGIN_ROOT CLAUDE_CONFIG_DIR="$TMPCLAUDECONFIG" OPENCODE_CONFIG_DIR="$TMPOPENCODE" bash "${CACHE_RND}/rnd-dir.sh" -c 2>&1)" || RND_PREC_EXIT=$?

assert_eq "rnd-dir.sh -c CLAUDE_CONFIG_DIR+OPENCODE_CONFIG_DIR exits 0" "0" "$RND_PREC_EXIT"

if [[ "$RND_PREC_RESULT" == "${TMPCLAUDECONFIG}"/* ]]; then
  assert_eq "CLAUDE_CONFIG_DIR takes precedence over OPENCODE_CONFIG_DIR" "yes" "yes"
else
  assert_eq "CLAUDE_CONFIG_DIR takes precedence over OPENCODE_CONFIG_DIR" "yes" "no: '$RND_PREC_RESULT'"
fi

# ---------------------------------------------------------------------------
# Regression: no platform env vars set — must default to $HOME/.claude
# ---------------------------------------------------------------------------
printf '%s\n' '--- Default: no platform env vars ---'

FAKEHOME3="${TMPBASE}/fakehome3"
mkdir -p "$FAKEHOME3"

RND_DEFAULT_RESULT=""
RND_DEFAULT_EXIT=0
RND_DEFAULT_RESULT="$(env -u CLAUDE_CONFIG_DIR -u CLAUDE_PLUGIN_ROOT -u DROID_CONFIG_DIR -u DROID_PLUGIN_ROOT -u OPENCODE_CONFIG_DIR -u OPENCODE_CONFIG HOME="$FAKEHOME3" bash "${CACHE_RND}/rnd-dir.sh" -c 2>&1)" || RND_DEFAULT_EXIT=$?

assert_eq "rnd-dir.sh -c with no platform vars exits 0" "0" "$RND_DEFAULT_EXIT"

if [[ "$RND_DEFAULT_RESULT" == "${FAKEHOME3}/.claude/"* ]]; then
  assert_eq "rnd-dir.sh -c defaults to \$HOME/.claude" "yes" "yes"
else
  assert_eq "rnd-dir.sh -c defaults to \$HOME/.claude" "yes" "no: '$RND_DEFAULT_RESULT'"
fi

report
