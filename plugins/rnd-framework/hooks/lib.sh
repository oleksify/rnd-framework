#!/usr/bin/env bash
# hooks/lib.sh — Shared utilities for rnd-framework hooks.
# Source from any hook: source "$(dirname "$0")/lib.sh"

_HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${_HOOKS_DIR}/.." && pwd)"

ALLOW_JSON='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'

# Extract file_path from hook JSON input
hook_file_path() {
  printf '%s' "$1" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true
}

# Extract command from hook JSON input
hook_command() {
  printf '%s' "$1" | jq -r '.tool_input.command // empty' 2>/dev/null || true
}

# Extract tool_name from hook JSON input
hook_tool_name() {
  printf '%s' "$1" | jq -r '.tool_name // empty' 2>/dev/null || true
}

# Extract agent_type from hook JSON input (empty string if absent)
hook_agent_type() {
  printf '%s' "$1" | jq -r '.agent_type // empty' 2>/dev/null || true
}

# Check if path is an .rnd/ artifact
is_rnd_path() {
  printf '%s' "$1" | grep -q '\.rnd/'
}

# Resolve RND_DIR (pass flags like -c as arguments)
resolve_rnd_dir() {
  "${PLUGIN_ROOT}/lib/rnd-dir.sh" "$@" 2>/dev/null || echo ""
}

# Emit allow decision (PreToolUse)
hook_allow() {
  echo "$ALLOW_JSON"
}

# Block operation — message to stderr, exit 2
hook_block() {
  echo "$1" >&2
  exit 2
}
