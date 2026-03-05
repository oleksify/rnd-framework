#!/usr/bin/env bash
# rnd-dir.sh — Compute the RND artifacts directory path.
#
# Usage:
#   rnd-dir.sh          Print session path if .current-session exists, else base dir
#   rnd-dir.sh -c       Create directory structure; generate session ID if needed; print session path
#   rnd-dir.sh --finish Delete .current-session (idempotent); exit 0
#   rnd-dir.sh --base   Print just the project base dir; never creates directories
#
# Session path: <base>/sessions/<YYYYMMDD-HHMMSS-XXXX>/
# Base path:    <claude-config-dir>/.rnd/<project-slug>/
# where project-slug = <basename>-<8char-sha256-of-pwd>
#
# Config dir priority:
#   1. CLAUDE_PLUGIN_ROOT (strip /plugins/cache/... suffix)
#   2. CLAUDE_CONFIG_DIR (set by Claude Code in shell environment)
#   3. ~/.claude (last resort)

set -euo pipefail

# --- Derive Claude config directory ---
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  # Strip /plugins/cache/... suffix to get config root
  CONFIG_DIR="${CLAUDE_PLUGIN_ROOT%%/plugins/cache/*}"
  # If stripping didn't change anything (unexpected layout), fall back
  if [ "$CONFIG_DIR" = "$CLAUDE_PLUGIN_ROOT" ]; then
    CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  fi
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  CONFIG_DIR="$CLAUDE_CONFIG_DIR"
else
  CONFIG_DIR="$HOME/.claude"
fi

# --- Compute project slug ---
PROJECT_DIR="$(pwd)"
BASENAME="$(basename "$PROJECT_DIR")"

# 8-char hex hash of the full path for uniqueness (~4B collision space)
if command -v shasum >/dev/null 2>&1; then
  HASH=$(printf '%s' "$PROJECT_DIR" | shasum -a 256 | cut -c1-8)
elif command -v sha256sum >/dev/null 2>&1; then
  HASH=$(printf '%s' "$PROJECT_DIR" | sha256sum | cut -c1-8)
else
  # Fallback: use cksum-based hash (less ideal but always available)
  HASH=$(printf '%s' "$PROJECT_DIR" | cksum | awk '{printf "%08x", $1}' | cut -c1-8)
fi

SLUG="${BASENAME}-${HASH}"
BASE_DIR="${CONFIG_DIR}/.rnd/${SLUG}"
SESSION_FILE="${BASE_DIR}/.current-session"

FLAG="${1:-}"

# --- Handle --base flag ---
if [ "$FLAG" = "--base" ]; then
  echo "$BASE_DIR"
  exit 0
fi

# --- Handle --finish flag ---
if [ "$FLAG" = "--finish" ]; then
  rm -f "$SESSION_FILE"
  exit 0
fi

# --- Handle -c flag: create directory structure ---
if [ "$FLAG" = "-c" ]; then
  # Reuse existing session ID or generate a new one
  if [ -f "$SESSION_FILE" ]; then
    SESSION_ID="$(cat "$SESSION_FILE")"
    # Validate format: YYYYMMDD-HHMMSS-XXXX
    if ! echo "$SESSION_ID" | grep -qE '^[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$'; then
      echo "error: invalid session ID format in ${SESSION_FILE}: '${SESSION_ID}'" >&2
      exit 1
    fi
  else
    TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
    HEX="$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-4)"
    SESSION_ID="${TIMESTAMP}-${HEX}"
    mkdir -p "$BASE_DIR"
    # Atomic write: use noclobber to prevent race condition
    if ( set -o noclobber; printf '%s' "$SESSION_ID" > "$SESSION_FILE" ) 2>/dev/null; then
      : # We created the session file
    else
      # Another process created it first; read theirs
      SESSION_ID="$(cat "$SESSION_FILE")"
      if ! echo "$SESSION_ID" | grep -qE '^[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$'; then
        echo "error: invalid session ID format in ${SESSION_FILE}: '${SESSION_ID}'" >&2
        exit 1
      fi
    fi
  fi
  SESSION_DIR="${BASE_DIR}/sessions/${SESSION_ID}"
  mkdir -p "${SESSION_DIR}/builds" "${SESSION_DIR}/verifications" "${SESSION_DIR}/integration"
  echo "$SESSION_DIR"
  exit 0
fi

# --- No flags: output session path if session active, else base dir ---
if [ -f "$SESSION_FILE" ]; then
  SESSION_ID="$(cat "$SESSION_FILE")"
  if ! echo "$SESSION_ID" | grep -qE '^[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$'; then
    echo "error: invalid session ID format in ${SESSION_FILE}: '${SESSION_ID}'" >&2
    exit 1
  fi
  echo "${BASE_DIR}/sessions/${SESSION_ID}"
else
  echo "$BASE_DIR"
fi
