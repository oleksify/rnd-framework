#!/usr/bin/env bash
# hooks/pre-compact.sh — PreCompact hook for rnd-framework plugin.
# Saves pipeline state to $RND_DIR/compact-state.json before context compaction.
#
# Fire-and-forget: exits 0 always, produces no stdout.
# Reads: protocol.md (fallback plan.md), builds/*-manifest.md, iteration-log.md
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Matches both current builder convention (M<NN>-T<NN>-<uuid>-manifest.md,
# uuid an 8-hex string) and the legacy form (T<id>-manifest.md).
readonly MANIFEST_REGEX='^(T[0-9]+|M[0-9]+-T[0-9]+-[0-9a-f]{8})-manifest\.md$'
readonly PLAN_HEAD_LINES=5

# ---------------------------------------------------------------------------
# plan_summary: first N lines of protocol.md (fallback plan.md), or "no plan"
# ---------------------------------------------------------------------------

if [[ -f "${session_dir}/protocol.md" ]]; then
  plan_file="${session_dir}/protocol.md"
elif [[ -f "${session_dir}/plan.md" ]]; then
  plan_file="${session_dir}/plan.md"
else
  plan_file=""
fi

if [[ -n "$plan_file" ]]; then
  plan_summary="$(awk -v n="$PLAN_HEAD_LINES" 'NR<=n' "$plan_file" 2>/dev/null || true)"
  [[ -n "$plan_summary" ]] || plan_summary="no plan"
else
  plan_summary="no plan"
fi

# ---------------------------------------------------------------------------
# currentTaskId: basename of most recently modified *-manifest.md, or null
# ---------------------------------------------------------------------------

builds_dir="${session_dir}/builds"
current_task_id_json="null"
if [[ -d "$builds_dir" ]]; then
  # ls -t sorts by mtime descending; first match is most recent
  most_recent=""
  while IFS= read -r f; do
    fname="$(basename "$f")"
    if [[ "$fname" =~ $MANIFEST_REGEX ]]; then
      most_recent="$fname"
      break
    fi
  done < <(ls -t "${builds_dir}/"*-manifest.md 2>/dev/null || true)
  if [[ -n "$most_recent" ]]; then
    task_id="${most_recent%-manifest.md}"
    current_task_id_json="$(printf '%s' "$task_id" | jq -Rs .)"
  fi
fi

# ---------------------------------------------------------------------------
# iterationCount: line count of iteration-log.md, or 0
# ---------------------------------------------------------------------------

log_file="${session_dir}/iteration-log.md"
iteration_count=0
if [[ -f "$log_file" ]]; then
  iteration_count="$(awk 'END{print NR}' "$log_file" 2>/dev/null || printf '0')"
  iteration_count="${iteration_count// /}"
  [[ "$iteration_count" =~ ^[0-9]+$ ]] || iteration_count=0
fi

# ---------------------------------------------------------------------------
# verificationNeedle: 8-char random hex string
# ---------------------------------------------------------------------------

needle="$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || printf '00000000')"

# ---------------------------------------------------------------------------
# Write compact-state.json using jq
# ---------------------------------------------------------------------------

jq -cn \
  --arg plan_summary "$plan_summary" \
  --argjson current_task_id "$current_task_id_json" \
  --argjson iteration_count "$iteration_count" \
  --arg saved_at "$(iso_timestamp)" \
  --arg verification_needle "$needle" \
  '{plan_summary:$plan_summary,current_task_id:$current_task_id,iteration_count:$iteration_count,saved_at:$saved_at,verification_needle:$verification_needle}' \
  > "${session_dir}/compact-state.json" 2>/dev/null || true

exit 0
