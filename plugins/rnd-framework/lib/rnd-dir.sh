#!/usr/bin/env bash
# rnd-dir.sh — Compute the RND artifacts directory path.
#
# Usage:
#   rnd-dir.sh          Print the RND directory path
#   rnd-dir.sh -c       Create the directory structure and print the path
#
# The path is: <claude-config-dir>/.rnd/<project-slug>/
# where project-slug = <basename>-<6char-sha256-of-pwd>
#
# Config dir is derived from CLAUDE_PLUGIN_ROOT when available,
# otherwise falls back to ~/.claude.

set -euo pipefail

# --- Derive Claude config directory ---
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  # Strip /plugins/cache/... suffix to get config root
  CONFIG_DIR="${CLAUDE_PLUGIN_ROOT%%/plugins/cache/*}"
  # If stripping didn't change anything (unexpected layout), fall back
  if [ "$CONFIG_DIR" = "$CLAUDE_PLUGIN_ROOT" ]; then
    CONFIG_DIR="$HOME/.claude"
  fi
else
  CONFIG_DIR="$HOME/.claude"
fi

# --- Compute project slug ---
PROJECT_DIR="$(pwd)"
BASENAME="$(basename "$PROJECT_DIR")"

# 6-char hex hash of the full path for uniqueness
if command -v shasum >/dev/null 2>&1; then
  HASH=$(printf '%s' "$PROJECT_DIR" | shasum -a 256 | cut -c1-6)
elif command -v sha256sum >/dev/null 2>&1; then
  HASH=$(printf '%s' "$PROJECT_DIR" | sha256sum | cut -c1-6)
else
  # Fallback: use cksum-based hash (less ideal but always available)
  HASH=$(printf '%s' "$PROJECT_DIR" | cksum | awk '{printf "%06x", $1}' | cut -c1-6)
fi

SLUG="${BASENAME}-${HASH}"
RND_DIR="${CONFIG_DIR}/.rnd/${SLUG}"

# --- Optionally create directory structure ---
if [ "${1:-}" = "-c" ]; then
  mkdir -p "$RND_DIR/builds" "$RND_DIR/verifications" "$RND_DIR/integration"
  # Create iteration-log.md if it doesn't exist
  [ -f "$RND_DIR/iteration-log.md" ] || touch "$RND_DIR/iteration-log.md"
fi

echo "$RND_DIR"
