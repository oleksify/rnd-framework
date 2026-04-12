#!/usr/bin/env bash
# hooks/glob-grep-gate.sh — PreToolUse hook for Glob and Grep.
#
# Responsibilities:
#   1. Information barrier — blocks Glob/Grep operations targeting self-assessment
#      content to prevent the Verifier from accessing Builder reasoning via search.
#      Mirrors the barrier in read-gate.sh; must remain consistent with it.
#   2. Auto-allow .rnd/ path operations without a permission prompt.
#   3. No opinion for all other paths.
#
# The barrier check MUST precede the auto-allow check so that a .rnd/ path
# containing "self-assessment" is blocked rather than silently allowed.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly BARRIER_KEYWORD="self-assessment"
readonly VERIFIER_KEYWORD="verifier"

parse_input
path="$(printf '%s' "$TOOL_INPUT" | jq -r '.path // ""' 2>/dev/null || true)"
pattern="$(printf '%s' "$TOOL_INPUT" | jq -r '.pattern // ""' 2>/dev/null || true)"

# Check both path and pattern for the barrier keyword (case-insensitive).
path_lower="$(_lower "$path")"
pattern_lower="$(_lower "$pattern")"

if [[ "$path_lower" == *"${BARRIER_KEYWORD}"* ]] || [[ "$pattern_lower" == *"${BARRIER_KEYWORD}"* ]]; then
  agent_lower="$(_lower "${AGENT_TYPE}")"
  if [[ -z "$agent_lower" ]] || [[ "$agent_lower" == *"${VERIFIER_KEYWORD}"* ]]; then
    block_msg "INFORMATION BARRIER: self-assessment files are write-only records for the orchestrator. Direct reading is blocked to maintain information barriers between Builder and Verifier."
  fi
  # Non-verifier agent: no opinion, exit 0
  exit 0
fi

if [[ -n "$path" ]] && is_plugin_artifact_path "$path"; then
  allow_json
  exit 0
fi
exit 0
