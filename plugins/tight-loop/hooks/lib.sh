#!/usr/bin/env bash
# hooks/lib.sh — Shared bash utilities for tight-loop hooks.
# Source from any hook: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# ---------------------------------------------------------------------------
# String utilities (bash 3.2 compatible)
# ---------------------------------------------------------------------------

# Lowercase a string. Uses tr instead of ${var,,} for macOS stock bash (3.2) compat.
_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ---------------------------------------------------------------------------
# Path utilities
# ---------------------------------------------------------------------------

# Returns 0 if path is under the .tight-loop/ plugin artifact directory
# within a .claude config directory.
is_plugin_artifact_path() {
  local path="$1"
  [[ "$path" == /* ]] || return 1
  [[ "$path" =~ \.claude[^/]*/.*\.tight-loop/ ]]
}

# Returns 0 if the file has a recognised source-code extension.
is_code_file() {
  local path="$1"
  local ext="${path##*.}"
  ext="$(_lower "$ext")"
  case "$ext" in
    ts|tsx|js|jsx|mjs|cjs|\
    py|rb|go|rs|java|\
    c|cpp|h|hpp|cs|\
    swift|kt|scala|\
    sh|bash|zsh|fish|\
    lua|php|vue|svelte|\
    ex|exs|\
    lean|kk|ml|mli)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Hook response output
# ---------------------------------------------------------------------------

# Outputs the PreToolUse allow JSON to stdout.
allow_json() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
}

# Outputs an advisory JSON to stdout via top-level systemMessage.
advisory_json() {
  system_message_json "$1"
}

# Outputs a system message JSON to stdout.
system_message_json() {
  local msg="$1"
  printf '{"systemMessage":%s}\n' "$(printf '%s' "$msg" | jq -Rs .)"
}

# Writes message to stderr and exits 2. Blocks a hook operation.
block_msg() {
  local msg="$1"
  printf '%s\n' "$msg" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Stdin parsing
# ---------------------------------------------------------------------------

# Reads all of stdin into a variable, then extracts TOOL_NAME, TOOL_INPUT,
# and AGENT_TYPE using a single jq call. Sets those variables in the caller's scope.
# On malformed input, sets all to empty strings.
parse_input() {
  local raw parsed
  raw="$(cat)"
  parsed="$(printf '%s' "$raw" | jq -r '
    [(.tool_name // ""), (.tool_input // {} | tojson), (.agent_type // "")]
    | join("\t")' 2>/dev/null || true)"
  if [[ -n "$parsed" ]]; then
    IFS=$'\t' read -r TOOL_NAME TOOL_INPUT AGENT_TYPE <<< "$parsed"
  else
    TOOL_NAME=""
    TOOL_INPUT=""
    AGENT_TYPE=""
  fi
}

# Extracts file_path from a tool_input JSON string.
# Usage: fp="$(extract_file_path "$TOOL_INPUT")"
extract_file_path() {
  local tool_input="$1"
  printf '%s' "$tool_input" | jq -r '.file_path // ""' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Tight-loop directory resolution
# ---------------------------------------------------------------------------

# Returns the project base directory for tight-loop artifacts.
# Calls tight-dir.sh relative to the lib.sh location and prints the path.
# Prints nothing and returns 1 on failure.
tight_base_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local tight_script="${script_dir}/../lib/tight-dir.sh"

  if [[ ! -x "$tight_script" ]]; then
    return 1
  fi

  local result
  result="$("$tight_script" "$@" 2>/dev/null)" || return 1
  [[ -n "$result" ]] && printf '%s' "$result" || return 1
}

# ---------------------------------------------------------------------------
# Timestamps
# ---------------------------------------------------------------------------

# Outputs an ISO 8601 UTC timestamp without milliseconds (e.g. 2025-03-22T09:10:11Z).
iso_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

