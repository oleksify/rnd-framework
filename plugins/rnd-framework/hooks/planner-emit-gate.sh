#!/usr/bin/env bash
# hooks/planner-emit-gate.sh — SubagentStop hook.
# Blocks the rnd-planner agent from completing when its emitted
# validation-contract.md has any assertion missing a valid Shape: (a value in
# the x-shape-vocab controlled list) or a valid Confidence: (one of high,
# medium, stretch).
# The vocab is sourced at runtime from lib/event-schema.json — the single
# source of truth — so this gate never carries a duplicate copy of the list.
# Exits 2 (block) on violation, naming the offending assertion ID(s); never
# prompts the user. Exits 0 (no-opinion) for all other agents, when no active
# session exists, or when no validation-contract.md is present.
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

contract_path="${session_dir}/validation-contract.md"

if [[ ! -f "$contract_path" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Source the controlled Shape vocabulary from the schema SSOT.
# ---------------------------------------------------------------------------

schema_path="$(dirname "${BASH_SOURCE[0]}")/../lib/event-schema.json"

shape_vocab=""
if [[ -f "$schema_path" ]]; then
  shape_vocab="$(jq -r '."x-shape-vocab"[]' "$schema_path" 2>/dev/null || true)"
fi

# Without a readable vocab there is nothing to validate against — do not block.
if [[ -z "$shape_vocab" ]]; then
  exit 0
fi

# Membership test against newline-delimited vocab (bash 3.2 safe).
_in_shape_vocab() {
  local needle="$1"
  local term
  while IFS= read -r term; do
    [[ "$needle" == "$term" ]] && return 0
  done <<< "$shape_vocab"
  return 1
}

_valid_confidence() {
  case "$1" in
    high|medium|stretch) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Walk every `### M<N>.<area>.<slug>` assertion heading via the shared parser,
# then validate each assertion's Shape: and Confidence: values.
# ---------------------------------------------------------------------------

contract_content="$(< "$contract_path")"

offenders=""

while IFS=$'\t' read -r assertion_id assertion_shape assertion_confidence; do
  [[ -n "$assertion_id" ]] || continue

  bad=0

  if [[ -z "$assertion_shape" ]] || ! _in_shape_vocab "$assertion_shape"; then
    bad=1
  fi

  if [[ -z "$assertion_confidence" ]] || ! _valid_confidence "$assertion_confidence"; then
    bad=1
  fi

  if [[ "$bad" -eq 1 ]]; then
    offenders="${offenders}${offenders:+ }${assertion_id}"
  fi
done <<< "$(parse_contract_assertions "$contract_content")"

if [[ -n "$offenders" ]]; then
  first_id="${offenders%% *}"

  if [[ -n "${RND_DIR:-}" ]]; then
    bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
      "gate_fired" "$first_id" "planner_emit_gate" 2>/dev/null || true
  fi

  block_msg "planner-emit-gate: validation-contract.md has assertion(s) missing a valid Shape: or Confidence:.

Offending assertion ID(s): ${offenders}

Every \`### M<N>.<area>.<slug>\` assertion must declare:
  - Shape: one of the x-shape-vocab values in lib/event-schema.json
  - Confidence: one of high | medium | stretch

Re-emit the validation contract with both fields present and valid on every assertion.

Contract path: ${contract_path}"
fi

exit 0
