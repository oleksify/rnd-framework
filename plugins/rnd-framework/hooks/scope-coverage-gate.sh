#!/usr/bin/env bash
# hooks/scope-coverage-gate.sh — SubagentStop hook.
# Mechanically enforces the bidirectional scope lock once a plan declares
# deliverable coverage. Blocks the rnd-planner agent from completing when its
# emitted features.json and the frozen scope.json have drifted out of
# bijective coverage:
#   - scope_creep: a task's deliverableIds[] references a deliverable ID that
#     is NOT in scope.json, OR is an empty [] while the field is in use.
#   - scope_miss:  a scope.json deliverable is covered by ZERO tasks.
# The join is purely structural — deliverable IDs in scope.json
# (.deliverables[].id) against each task's features.json deliverableIds[].
# Exits 2 (block) on any violation, naming the offender(s); never prompts the
# user. Exits 0 (no-opinion) for all other agents, when no active session
# exists, when either artifact is absent, or for a legacy plan where no task
# carries a deliverableIds key at all.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

raw="$(cat)"

agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

agent_lower="$(_lower "$agent_type")"

if [[ "$agent_lower" != *"rnd-planner"* ]]; then
  exit 0
fi

session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -z "$session_dir" ]]; then
  exit 0
fi

scope_path="${session_dir}/scope.json"
features_path="${session_dir}/features.json"

if [[ ! -f "$scope_path" || ! -f "$features_path" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Legacy fast-path: if NO task carries a deliverableIds key at all, this plan
# predates the scope lock — the gate has no opinion and must not block it.
# ---------------------------------------------------------------------------

has_deliverable_field="$(jq -r '[.tasks[]? | has("deliverableIds")] | any' "$features_path" 2>/dev/null || true)"

if [[ "$has_deliverable_field" != "true" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Build the structural sets. Newline-delimited strings + while-read loops keep
# this bash-3.2 safe (no associative arrays, no mapfile). jq null-safety with
# // [] guards every array access.
# ---------------------------------------------------------------------------

scope_ids="$(jq -r '.deliverables[]?.id // empty' "$scope_path" 2>/dev/null || true)"

# Membership test against newline-delimited scope IDs.
_in_scope_ids() {
  local needle="$1"
  local term
  while IFS= read -r term; do
    [[ -n "$term" ]] || continue
    [[ "$needle" == "$term" ]] && return 0
  done <<< "$scope_ids"
  return 1
}

# ---------------------------------------------------------------------------
# scope_creep: a task whose deliverableIds[] references an unknown ID, OR an
# empty [] while the field is in use. One tab-separated record per task:
#   <task_id>\t<space-joined deliverableIds>
# ---------------------------------------------------------------------------

creep_offenders=""

while IFS=$'\t' read -r task_id deliverable_ids; do
  [[ -n "$task_id" ]] || continue

  bad=0

  if [[ -z "$deliverable_ids" ]]; then
    # Field present but empty [] — an orphan task referencing nothing.
    bad=1
  else
    while IFS= read -r one_id; do
      [[ -n "$one_id" ]] || continue
      if ! _in_scope_ids "$one_id"; then
        bad=1
      fi
    done <<< "$(printf '%s' "$deliverable_ids" | tr ' ' '\n')"
  fi

  if [[ "$bad" -eq 1 ]]; then
    creep_offenders="${creep_offenders}${creep_offenders:+ }${task_id}"
  fi
done <<< "$(jq -r '.tasks[]? | select(has("deliverableIds")) | "\(.id)\t\((.deliverableIds // []) | join(" "))"' "$features_path" 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# scope_miss: a scope.json deliverable covered by ZERO tasks. Collect the
# union of every task's deliverableIds, then find scope IDs absent from it.
# ---------------------------------------------------------------------------

covered_ids="$(jq -r '[.tasks[]? | (.deliverableIds // [])[]] | .[]?' "$features_path" 2>/dev/null || true)"

_is_covered() {
  local needle="$1"
  local term
  while IFS= read -r term; do
    [[ -n "$term" ]] || continue
    [[ "$needle" == "$term" ]] && return 0
  done <<< "$covered_ids"
  return 1
}

miss_offenders=""

while IFS= read -r scope_id; do
  [[ -n "$scope_id" ]] || continue
  if ! _is_covered "$scope_id"; then
    miss_offenders="${miss_offenders}${miss_offenders:+ }${scope_id}"
  fi
done <<< "$scope_ids"

# ---------------------------------------------------------------------------
# Emit gate_fired then block. The violation KIND is carried in the 4th arg
# (assertion_id slot) so the stats view can split creep vs miss. Creep is
# reported first when both are present.
# ---------------------------------------------------------------------------

if [[ -n "$creep_offenders" ]]; then
  first_id="${creep_offenders%% *}"

  if [[ -n "${RND_DIR:-}" ]]; then
    bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
      "gate_fired" "$first_id" "scope_coverage_gate" "scope_creep" 2>/dev/null || true
  fi

  block_msg "scope-coverage-gate: scope creep — task(s) reference a deliverable ID absent from scope.json, or carry an empty deliverableIds[].

Offending task ID(s): ${creep_offenders}

Every task's deliverableIds[] must reference at least one deliverable ID present in scope.json (.deliverables[].id). An empty [] is an orphan task.

Scope path:    ${scope_path}
Features path: ${features_path}"
fi

if [[ -n "$miss_offenders" ]]; then
  first_id="${miss_offenders%% *}"

  if [[ -n "${RND_DIR:-}" ]]; then
    bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
      "gate_fired" "$first_id" "scope_coverage_gate" "scope_miss" 2>/dev/null || true
  fi

  block_msg "scope-coverage-gate: scope miss — deliverable(s) in scope.json are covered by zero tasks.

Uncovered deliverable ID(s): ${miss_offenders}

Every scope.json deliverable must be claimed by at least one task via deliverableIds[].

Scope path:    ${scope_path}
Features path: ${features_path}"
fi

exit 0
