#!/usr/bin/env bash
# hooks/lib.sh — Shared bash utilities for rnd-framework hooks.
# Source from any hook: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# ---------------------------------------------------------------------------
# Path utilities
# ---------------------------------------------------------------------------

# Returns 0 if path is under a plugin artifact directory (.rnd/, .rnd/, etc.)
# within a .claude config directory.
is_plugin_artifact_path() {
  local path="$1"
  [[ "$path" =~ \.claude[^/]*/.*\.rnd/ ]]
}

# Backward-compatible alias.
is_rnd_path() { is_plugin_artifact_path "$1"; }

# Returns 0 if path contains plugins/cache/ under a .claude config directory.
is_plugin_cache_path() {
  local path="$1"
  [[ "$path" =~ \.claude[^/]*/.*plugins/cache/ ]]
}

# Returns 0 if path contains learnings/ under a .claude config directory.
is_learnings_path() {
  local path="$1"
  [[ "$path" =~ \.claude[^/]*/.*learnings/ ]]
}

# Returns 0 if the file has a recognised source-code extension.
is_code_file() {
  local path="$1"
  local ext="${path##*.}"
  ext="${ext,,}"
  case "$ext" in
    ts|tsx|js|jsx|mjs|cjs|\
    py|rb|go|rs|java|\
    c|cpp|h|hpp|cs|\
    swift|kt|scala|\
    sh|bash|zsh|fish|\
    lua|php|vue|svelte|\
    ex|exs)
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

# Outputs an advisory JSON to stdout. Properly JSON-escapes the message via jq.
advisory_json() {
  local msg="$1"
  printf '{"hookSpecificOutput":{"additionalContext":%s}}\n' "$(printf '%s' "$msg" | jq -Rs .)"
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
# and AGENT_TYPE using jq. Sets those variables in the caller's scope.
# On malformed input, sets all to empty strings.
parse_input() {
  local raw
  raw="$(cat)"
  TOOL_NAME="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  TOOL_INPUT="$(printf '%s' "$raw" | jq -c '.tool_input // {}' 2>/dev/null || true)"
  AGENT_TYPE="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"
}

# Extracts file_path from a tool_input JSON string.
# Usage: fp="$(extract_file_path "$TOOL_INPUT")"
extract_file_path() {
  local tool_input="$1"
  printf '%s' "$tool_input" | jq -r '.file_path // ""' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# RND directory resolution
# ---------------------------------------------------------------------------

# Calls rnd-dir.sh relative to the lib.sh location and prints the path.
# Accepts optional flags (e.g. -c, --base) passed through to rnd-dir.sh.
# Prints nothing and returns 1 on failure.
resolve_rnd_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local rnd_script="${script_dir}/../lib/rnd-dir.sh"
  if [[ ! -x "$rnd_script" ]]; then
    return 1
  fi
  local result
  result="$("$rnd_script" "$@" 2>/dev/null)" || return 1
  [[ -n "$result" ]] && printf '%s' "$result" || return 1
}

# Returns the active session directory path when it exists and contains /sessions/.
# Prints nothing and returns 1 otherwise.
active_session_dir() {
  local dir
  dir="$(resolve_rnd_dir)" || return 1
  [[ "$dir" == */sessions/* ]] || return 1
  [[ -d "$dir" ]] || return 1
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Timestamps
# ---------------------------------------------------------------------------

# Outputs an ISO 8601 UTC timestamp without milliseconds (e.g. 2025-03-22T09:10:11Z).
iso_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# ---------------------------------------------------------------------------
# FP utilities
# ---------------------------------------------------------------------------

# Extracts a jq field from JSON; prints the value or empty string; always returns 0.
jq_extract() {
  local json="$1"
  local field="$2"
  local result
  result="$(printf '%s' "$json" | jq -r "${field} // empty" 2>/dev/null)" || true
  printf '%s' "$result"
  return 0
}

# Returns 0 when value is non-empty, 1 when empty; prints optional message to stderr on empty.
# Usage: guard_nonempty "$val" "description" || return 0
guard_nonempty() {
  local value="$1"
  local message="${2:-}"
  if [[ -n "$value" ]]; then
    return 0
  fi
  [[ -z "$message" ]] || printf '%s\n' "$message" >&2
  return 1
}

# Reads stdin, removes YAML frontmatter (lines between first --- and second --- inclusive), prints remainder.
strip_frontmatter() {
  awk '
    /^---$/ && !seen_open { seen_open=1; next }
    /^---$/ && seen_open && !seen_close { seen_close=1; next }
    seen_close || !seen_open { print }
  '
}

# Reads stdin line-by-line, applies the named function to each line, prints results.
map_lines() {
  local fn="$1"
  local line
  while IFS= read -r line; do
    "$fn" "$line"
  done
}

# Reads stdin line-by-line, prints only lines where the named function returns 0.
filter_lines() {
  local fn="$1"
  local line
  while IFS= read -r line; do
    if "$fn" "$line"; then
      printf '%s\n' "$line"
    fi
  done
}

# Reads stdin line-by-line, accumulates via function(accumulator, line), prints final accumulator.
reduce_lines() {
  local fn="$1"
  local acc="$2"
  local line
  while IFS= read -r line; do
    acc="$("$fn" "$acc" "$line")"
  done
  printf '%s' "$acc"
}

# Pure alternative to parse_input: reads stdin JSON, prints tool_name, tool_input_json, agent_type on 3 lines; always returns 0.
parse_input_stdout() {
  local raw
  raw="$(cat)"
  local tool_name tool_input agent_type
  tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null)" || tool_name=""
  tool_input="$(printf '%s' "$raw" | jq -c '.tool_input // {}' 2>/dev/null)" || tool_input=""
  agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null)" || agent_type=""
  printf '%s\n%s\n%s\n' "$tool_name" "$tool_input" "$agent_type"
  return 0
}
