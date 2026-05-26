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
# containing a barrier-protected pattern (self-assessment, /briefs/, /cleanup/)
# is blocked rather than silently allowed.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

parse_input
path="$(printf '%s' "$TOOL_INPUT" | jq -r '.path // ""' 2>/dev/null || true)"
pattern="$(printf '%s' "$TOOL_INPUT" | jq -r '.pattern // ""' 2>/dev/null || true)"
path_lower="$(_lower "$path")"
pattern_lower="$(_lower "$pattern")"

# Block verifier/unknown agents that touch self-assessment or briefs/ content.
# Check path, pattern, AND their concatenation — a Glob with
# `path=/.../.rnd/sessions/x` and `pattern=/cleanup/*.md` only looks
# barrier-violating when the two are joined.
if is_barrier_violation "$path" "${AGENT_TYPE}" \
   || is_barrier_violation "$pattern" "${AGENT_TYPE}" \
   || is_barrier_violation "${path}/${pattern}" "${AGENT_TYPE}"; then
  block_msg "INFORMATION BARRIER: self-assessment files and briefs/ artifacts are records written for the orchestrator and the user — not for the Verifier. Direct reading is blocked to maintain information barriers between Builder and Verifier."
fi

# Non-verifier agent touching self-assessment, briefs/, or cleanup/: no-opinion, not auto-allow.
#
# The /briefs/ and /cleanup/ checks are anchored on .rnd/ to mirror
# is_barrier_violation in lib.sh — project source paths like /repo/src/briefs/
# are not artifact-tree paths and should fall through to no-opinion below.
# The self-assessment check is intentionally left unanchored (same as lib.sh).
if [[ "$path_lower" == *"self-assessment"* ]] || [[ "$pattern_lower" == *"self-assessment"* ]] \
   || [[ "$path_lower" =~ \.rnd/.*briefs/ ]] || [[ "$pattern_lower" =~ \.rnd/.*briefs/ ]] \
   || [[ "$path_lower" =~ \.rnd/.*cleanup/ ]] || [[ "$pattern_lower" =~ \.rnd/.*cleanup/ ]]; then
  exit 0
fi

if [[ -n "$path" ]] && is_plugin_artifact_path "$path"; then
  allow_json
  exit 0
fi
exit 0
