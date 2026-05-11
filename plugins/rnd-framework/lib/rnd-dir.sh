#!/usr/bin/env bash
# rnd-dir.sh — Compute the RND artifacts directory path.
#
# Usage:
#   rnd-dir.sh              Print session path if .current-session exists, else base dir
#   rnd-dir.sh -c           Create directory structure; generate session ID if needed; print session path
#   rnd-dir.sh --finish     Delete .current-session (idempotent); exit 0
#   rnd-dir.sh --base       Print just the branch-scoped project base dir; never creates directories
#   rnd-dir.sh --calibration Print <slug-dir>/calibration.jsonl (un-partitioned, slug root); never creates directories
#   rnd-dir.sh --roadmap    Print <base-dir>/roadmap.md; copies from default branch if absent
#   rnd-dir.sh --facts      Print <base-dir>/project-facts.md; copies from default branch if absent
#
# Session path: <base>/sessions/<YYYYMMDD-HHMMSS-XXXX>/
# Base path:    <claude-config-dir>/.rnd/<project-slug>/branches/<branch>/
# Slug path:    <claude-config-dir>/.rnd/<project-slug>/   (calibration lives here)

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=plugin-dir-base.sh
source "${_SCRIPT_DIR}/plugin-dir-base.sh" ".rnd" "${1:-}"

# Capture slug-level dir before branch partitioning.
# plugin-dir-base.sh sets BASE_DIR = <config>/.rnd/<slug>
_bk_slug_dir="$BASE_DIR"

# --calibration: returns the un-partitioned slug-root path.
# Dispatched here (before branch redefinition) so SLUG_DIR is used directly.
[[ "$FLAG" = "--calibration" ]] && { echo "${_bk_slug_dir}/calibration.jsonl"; exit 0; }

# --- Resolve branch name ---
_bk_resolve_branch() {
  local _branch
  if _branch="$(git symbolic-ref --short HEAD 2>/dev/null)"; then
    printf '%s' "$_branch"
    return 0
  fi

  local _sha
  if _sha="$(git rev-parse --short HEAD 2>/dev/null)"; then
    printf 'detached-%s' "$_sha"
    return 0
  fi

  printf 'no-git'
}

_bk_branch="$(_bk_resolve_branch)"

# Sanitize: reject branch names containing ".." (path traversal risk).
if [[ "$_bk_branch" == *..* ]]; then
  printf 'error: branch name contains ".." which is not allowed: %s\n' "$_bk_branch" >&2
  exit 1
fi

# Redefine BASE_DIR and SESSION_FILE to branch-scoped paths.
BASE_DIR="${_bk_slug_dir}/branches/${_bk_branch}"
SESSION_FILE="${BASE_DIR}/.current-session"

# --- Inheritance helper ---
# Copies <file> from the default branch's BASE_DIR to the current BASE_DIR
# if: we're not on the default branch AND the file is absent in current BASE_DIR.
_bk_inherit_if_missing() {
  local _file_basename="$1"
  local _default_branch="$2"

  # Skip self-copy when already on the default branch.
  [[ "$_bk_branch" = "$_default_branch" ]] && return 0

  local _target="${BASE_DIR}/${_file_basename}"

  # Already present — nothing to do.
  [[ -f "$_target" ]] && return 0

  local _source="${_bk_slug_dir}/branches/${_default_branch}/${_file_basename}"
  [[ -f "$_source" ]] || return 0

  mkdir -p "$BASE_DIR"
  cp "$_source" "$_target"
}

# --- Resolve default branch for inheritance ---
_bk_resolve_default_branch() {
  local _ref
  if _ref="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s' "${_ref#refs/remotes/origin/}"
    return 0
  fi

  if [[ -d "${_bk_slug_dir}/branches/main" ]]; then
    printf 'main'
    return 0
  fi

  if [[ -d "${_bk_slug_dir}/branches/master" ]]; then
    printf 'master'
    return 0
  fi

  # No default branch determinable — return empty; caller skips copy.
  printf ''
}

# --- Flag dispatch ---

[[ "$FLAG" = "--base"   ]] && { echo "$BASE_DIR"; exit 0; }

[[ "$FLAG" = "--finish" ]] && { rm -f "$SESSION_FILE"; exit 0; }

if [[ "$FLAG" = "--roadmap" ]]; then
  _bk_default="$(_bk_resolve_default_branch)"
  [[ -n "$_bk_default" ]] && _bk_inherit_if_missing "roadmap.md" "$_bk_default"
  echo "${BASE_DIR}/roadmap.md"
  exit 0
fi

if [[ "$FLAG" = "--facts" ]]; then
  _bk_default="$(_bk_resolve_default_branch)"
  [[ -n "$_bk_default" ]] && _bk_inherit_if_missing "project-facts.md" "$_bk_default"
  echo "${BASE_DIR}/project-facts.md"
  exit 0
fi

if [[ "$FLAG" = "-c" ]]; then
  _plugin_dir_create_session builds verifications integration

  # Cache file lives at <.rnd-root>/.active-base-dir — hardcoded in lib.sh::active_session_dir.
  # ${_bk_slug_dir%/*} strips the <slug> component, reaching <config>/.rnd.
  printf '%s' "$BASE_DIR" > "${_bk_slug_dir%/*}/.active-base-dir" 2>/dev/null || true
  exit 0
fi

_plugin_dir_current_or_base
