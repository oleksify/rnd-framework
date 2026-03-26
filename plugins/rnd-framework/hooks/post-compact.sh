#!/usr/bin/env bash
# hooks/post-compact.sh — Re-injects pipeline state after context compaction.
# Reads compact-state.json and outputs an advisory with restored state and
# a needle-in-the-haystack verification challenge. Always exits 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

rnd_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$rnd_dir" ]] || exit 0

state_file="${rnd_dir}/compact-state.json"
[[ -f "$state_file" ]] || exit 0

state_json="$(cat "$state_file" 2>/dev/null || true)"
plan="$(jq_extract "$state_json" '.planSummary')"
[[ -n "$plan" ]] || exit 0

task="$(jq_extract "$state_json" '.currentTaskId')"
task="${task:-unknown}"
iter="$(jq_extract "$state_json" '.iterationCount')"
iter="${iter:-0}"
saved="$(jq_extract "$state_json" '.savedAt')"
saved="${saved:-unknown}"
needle="$(jq_extract "$state_json" '.verificationNeedle')"

msg="Pipeline state restored after compaction:
  Plan: ${plan}
  Current task: ${task}
  Iteration: ${iter}
  State saved at: ${saved}"

if [[ -n "$needle" ]]; then
  msg="${msg}

VERIFICATION CHECK: Confirm your context survived compaction by stating: (1) current task ID: ${task}, (2) iteration count: ${iter}, (3) needle: ${needle}. If you cannot answer these, re-read \$RND_DIR/plan.md before continuing."
fi

advisory_json "$msg"
exit 0
