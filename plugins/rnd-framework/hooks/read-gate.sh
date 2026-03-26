#!/usr/bin/env bash
# PreToolUse hook for Read: enforces the information barrier and auto-allows .rnd/, plugin cache, and learnings reads.
#
# Four responsibilities:
#   1. Information barrier — blocks reads of self-assessment files to prevent the
#      Verifier from anchoring on Builder reasoning.
#   2. Auto-allow plugin cache — permits reads from plugins/cache/ paths without prompting.
#   3. Auto-allow learnings — permits reads from learnings/ paths without prompting.
#   4. Auto-allow .rnd/ — permits reads targeting .rnd/ paths without prompting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

readonly BARRIER_KEYWORD="self-assessment"
readonly VERIFIER_KEYWORD="verifier"
readonly PROOF_GATE_KEYWORD="proof-gate"

parse_input
file_path="$(extract_file_path "$TOOL_INPUT")"
agent_type="${AGENT_TYPE}"

lower="${file_path,,}"

if [[ "$lower" == *"${BARRIER_KEYWORD}"* ]]; then
  # Known non-verifier agents are allowed through.
  # Empty agent_type or any agent containing "verifier" is blocked.
  agent_lower="${agent_type,,}"
  if [[ -z "$agent_lower" ]] || [[ "$agent_lower" == *"${VERIFIER_KEYWORD}"* ]] || [[ "$agent_lower" == *"${PROOF_GATE_KEYWORD}"* ]]; then
    block_msg "INFORMATION BARRIER: self-assessment files are write-only records for the orchestrator. Direct reading is blocked to maintain information barriers between Builder and Verifier."
  fi
  # Non-verifier agent: fall through (no-opinion, exit 0)
  exit 0
fi

if is_plugin_cache_path "$file_path"; then
  allow_json
  exit 0
fi

if is_learnings_path "$file_path"; then
  allow_json
  exit 0
fi

if is_plugin_artifact_path "$file_path"; then
  allow_json
  exit 0
fi

# No opinion — exit 0 with no stdout
exit 0
