#!/usr/bin/env bash
# PreToolUse hook for Read: enforces the information barrier and auto-allows .rnd/, plugin cache, and learnings reads.
#
# Four responsibilities:
#   1. Information barrier — blocks reads of self-assessment files to prevent the
#      Verifier from anchoring on Builder reasoning.
#   2. Auto-allow plugin cache — permits reads from plugins/cache/ paths without prompting.
#   3. Auto-allow learnings — permits reads from learnings/ paths without prompting.
#   4. Auto-allow .rnd/ — permits reads targeting .rnd/ paths without prompting.

# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_input
file_path="$(extract_file_path "$TOOL_INPUT")"

if is_barrier_violation "$file_path" "${AGENT_TYPE}"; then
  block_msg "INFORMATION BARRIER: self-assessment files and briefs/ artifacts are records written for the orchestrator and the user — not for the Verifier. Direct reading is blocked to maintain information barriers between Builder and Verifier."
fi

# Re-plan barrier: a freshly-spawned Planner during a re-plan must not read
# its own prior canonical artifacts at the session root — the previous plan
# has been archived under prior-plans/replan-<k>/. Runs after the verifier
# barrier and before the .rnd/ auto-allow so the canonical paths (which
# live under .rnd/) don't silently slip through.
if is_replan_artifact_violation "$file_path" "${AGENT_TYPE}"; then
  block_msg "RE-PLAN BARRIER: prior plan artifacts at their canonical paths are hidden from a re-plan Planner spawn. Read the archive under prior-plans/ if needed, or proceed without prior context."
fi

# A non-verifier agent reading a self-assessment, briefs/, or cleanup/ path is
# not blocked, but is still not auto-allowed — defer to Claude Code's standard
# permission flow so the user sees the prompt rather than silently allowing
# the read.
#
# The /briefs/ and /cleanup/ checks are anchored on .rnd/ to mirror
# is_barrier_violation in lib.sh — project source paths like /repo/src/briefs/
# are not artifact-tree paths and should fall through to no-opinion below.
# The self-assessment check is intentionally left unanchored (same as lib.sh).
lower="$(_lower "$file_path")"
if [[ "$lower" == *"self-assessment"* ]] \
   || [[ "$lower" =~ \.rnd/.*briefs/ ]] \
   || [[ "$lower" =~ \.rnd/.*cleanup/ ]]; then
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
