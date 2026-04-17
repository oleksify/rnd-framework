#!/usr/bin/env bash
# plugin-dir-base.sh — Shared core logic for plugin artifact directory computation.
#
# INTERFACE (source this script; do not execute it directly):
#   source plugin-dir-base.sh <ARTIFACT_DIR_NAME> <FLAG>
#     $1  ARTIFACT_DIR_NAME — subdir under the Claude config dir (e.g. ".rnd")
#     $2  FLAG              — the flag passed to the wrapper (e.g. "", "-c", "--base", "--finish")
#
# After sourcing, the following are set in the caller's scope:
#   Variables:
#     CONFIG_DIR        — resolved Claude config directory
#     BASE_DIR          — <config-dir>/<artifact-dir-name>/<slug>
#     SESSION_FILE      — <base-dir>/.current-session
#     FLAG              — same as $2, for caller's flag dispatch
#     SESSION_ID_REGEX  — POSIX ERE pattern for valid session IDs
#   Functions:
#     _plugin_dir_validate_session_id <id> <file>
#       Returns 1 and prints to stderr if id does not match SESSION_ID_REGEX.
#       Uses [[ =~ ]]; never echo | grep.
#     _plugin_dir_create_session <subdir>...
#       Creates or reuses a session under BASE_DIR. Prints the session dir path.
#       Accepts a list of subdirs to create inside the session dir (e.g. "builds").
#       Exits 1 on invalid session ID format.
#
# Pre-conditions:
#   - Must be sourced, not executed directly.
#   - Caller has already run `set -euo pipefail`.
#   - $1 and $2 must be provided.
#   - shasum, sha256sum, or cksum must be available.
#
# Internal variables use the _pdb_ prefix. `local` is omitted (top-level source context).

# --- Arguments ---
_pdb_artifact_dir="$1"
FLAG="$2"

# --- Derive Claude config directory ---
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  CONFIG_DIR="${CLAUDE_PLUGIN_ROOT%%/plugins/cache/*}"
  if [[ "$CONFIG_DIR" = "$CLAUDE_PLUGIN_ROOT" ]]; then
    CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  fi
elif [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  CONFIG_DIR="$CLAUDE_CONFIG_DIR"
else
  CONFIG_DIR="$HOME/.claude"
fi

# --- Compute project slug ---
# Use git common-dir so all worktrees share one artifact base directory.
# Falls back to pwd when not inside a git repo.
if _pdb_git_raw="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  if [[ "$_pdb_git_raw" = /* ]]; then
    _pdb_hash_input="$_pdb_git_raw"
  else
    _pdb_hash_input="$(cd "$(dirname "$(pwd)/${_pdb_git_raw}")" && pwd)/$(basename "$_pdb_git_raw")"
  fi
  _pdb_basename="$(basename "$(dirname "$_pdb_hash_input")")"
else
  _pdb_hash_input="$(pwd)"
  _pdb_basename="$(basename "$_pdb_hash_input")"
fi

if command -v shasum >/dev/null 2>&1; then
  _pdb_hash=$(printf '%s' "$_pdb_hash_input" | shasum -a 256 | cut -c1-8)
elif command -v sha256sum >/dev/null 2>&1; then
  _pdb_hash=$(printf '%s' "$_pdb_hash_input" | sha256sum | cut -c1-8)
else
  _pdb_hash=$(printf '%s' "$_pdb_hash_input" | cksum | awk '{printf "%08x", $1}' | cut -c1-8)
fi

BASE_DIR="${CONFIG_DIR}/${_pdb_artifact_dir}/${_pdb_basename}-${_pdb_hash}"
SESSION_FILE="${BASE_DIR}/.current-session"
SESSION_ID_REGEX='^[0-9]{8}-[0-9]{6}-[0-9a-f]{4,8}$'

unset _pdb_artifact_dir _pdb_git_raw _pdb_hash_input _pdb_basename _pdb_hash

# --- Helper: validate session ID using [[ =~ ]] ---
_plugin_dir_validate_session_id() {
  local _sid="$1"
  local _file="$2"
  if ! [[ "$_sid" =~ $SESSION_ID_REGEX ]]; then
    echo "error: invalid session ID format in ${_file}: '${_sid}'" >&2
    return 1
  fi
}

# --- Helper: create or reuse a session; print session dir path ---
# Usage: _plugin_dir_create_session [subdir ...]
# Pre-condition: BASE_DIR, SESSION_FILE, SESSION_ID_REGEX are set.
# Post-condition: session dir and each listed subdir exist; session dir path printed to stdout.
_plugin_dir_create_session() {
  local _session_id _session_dir
  if [[ -f "$SESSION_FILE" ]]; then
    _session_id="$(< "$SESSION_FILE")"
    _plugin_dir_validate_session_id "$_session_id" "$SESSION_FILE" || exit 1
  else
    local _ts _hex
    _ts="$(date '+%Y%m%d-%H%M%S')"
    _hex="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n' | cut -c1-8)"
    _session_id="${_ts}-${_hex}"
    mkdir -p "$BASE_DIR"
    # Subshell: noclobber ensures atomic create-if-absent. Single command — no pipefail needed.
    if ! ( set -o noclobber; printf '%s' "$_session_id" > "$SESSION_FILE" ) 2>/dev/null; then
      _session_id="$(< "$SESSION_FILE")"
      _plugin_dir_validate_session_id "$_session_id" "$SESSION_FILE" || exit 1
    fi
  fi
  _session_dir="${BASE_DIR}/sessions/${_session_id}"
  mkdir -p "$_session_dir"
  local _sub
  for _sub in "$@"; do
    mkdir -p "${_session_dir}/${_sub}"
  done

  # Cache base dir for fast-path lookups in active_session_dir.
  # Non-atomic write; concurrent sessions may race. Acceptable: readers
  # tolerate stale values and fall back to the slow git+shasum path.
  local _rnd_parent="${BASE_DIR%/*}"
  printf '%s' "$BASE_DIR" > "${_rnd_parent}/.active-base-dir" 2>/dev/null || true

  echo "$_session_dir"
}

# --- Helper: print current session path or base dir ---
# Usage: _plugin_dir_current_or_base
# Pre-condition: BASE_DIR, SESSION_FILE, SESSION_ID_REGEX are set.
_plugin_dir_current_or_base() {
  if [[ -f "$SESSION_FILE" ]]; then
    local _sid
    _sid="$(< "$SESSION_FILE")"
    _plugin_dir_validate_session_id "$_sid" "$SESSION_FILE" || exit 1
    echo "${BASE_DIR}/sessions/${_sid}"
  else
    echo "$BASE_DIR"
  fi
}
