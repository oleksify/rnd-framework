#!/usr/bin/env bash
# hooks/shape-producer.sh — PostToolUse Write|Edit hook.
# Path-driven assertion_shape emitter.
#
# Fires when an agent writes a .../sessions/<id>/validation-contract.md OR a
# .../sessions/<id>/features.json file. Emits ONLY when BOTH files are present
# in the session dir: the contract supplies the assertions (and their Shape:/
# Confidence:), features.json supplies the assertion_id -> owning task_id map.
#
# The dual trigger + both-present gate makes emission robust to the planner's
# artifact write order (canonical order writes validation-contract.md BEFORE
# features.json): whichever file lands last fires this hook while both are
# present, so the correctly-mapped facts are always emitted. Emitting on both
# writes (when both present) produces duplicate lines, but shape_distribution
# and per_shape_fail_rate both read DISTINCT task_id/shape, so duplicates are
# harmless — no producer-side dedup is needed.
#
# task_id in each record is the owning TASK id (e.g. M2.T02.slug) resolved from
# features.json, never the assertion id — this is what lets per_shape_fail_rate
# JOIN against calibration.jsonl's taskId. An assertion not found in any task's
# assertionIds[] is SKIPPED (no wrong-task fact is ever written).
#
# Non-blocking: always exits 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

{
  raw="$(cat)"

  tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null || true)"

  case "$tool_name" in
    Write|Edit) ;;
    *) exit 0 ;;
  esac

  file_path="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"

  # Trigger on either planner artifact that carries the shape facts (the
  # contract) or the assertion->task map (features.json), under /sessions/.
  case "$file_path" in
    */sessions/*/validation-contract.md) ;;
    */sessions/*/features.json) ;;
    *) exit 0 ;;
  esac

  # Normalize to absolute if possible (handles relative path forms — FM1).
  abs_path="$(normalize_artifact_path "$file_path")"

  # Derive session_id from the (possibly normalized) path; fall back to raw.
  session_id="$(session_id_from_path "$abs_path")"

  if [[ -z "$session_id" ]]; then
    session_id="$(session_id_from_path "$file_path")"
  fi

  if [[ -z "$session_id" ]]; then
    exit 0
  fi

  # Session dir is the parent of whichever artifact triggered the hook.
  session_dir="${abs_path%/*}"

  if [[ ! -d "$session_dir" ]]; then
    session_dir="${file_path%/*}"
  fi

  contract_path="${session_dir}/validation-contract.md"
  features_path="${session_dir}/features.json"
  audit_path="${session_dir}/audit.jsonl"

  # Both-present gate: emit only when the contract AND the map both exist, so a
  # fact is never written with a missing or wrong task_id mapping.
  if [[ ! -f "$contract_path" ]] || [[ ! -f "$features_path" ]]; then
    exit 0
  fi

  contract_content="$(< "$contract_path")"
  features_json="$(< "$features_path")"

  if [[ -z "$contract_content" ]] || [[ -z "$features_json" ]]; then
    exit 0
  fi

  ts="$(iso_timestamp)"

  # Walk each assertion; emit one record per assertion that maps to a task.
  while IFS=$'\t' read -r assertion_id shape confidence; do
    [[ -n "$assertion_id" ]] || continue

    # Owning task_id = the task whose assertionIds[] contains this assertion.
    task_id="$(printf '%s' "$features_json" | jq -r --arg aid "$assertion_id" '
      .tasks[] | select(.assertionIds and (.assertionIds | index($aid) != null)) | .id
    ' 2>/dev/null | head -1 || true)"

    # No fallback: an unmapped assertion is skipped rather than emitted with a
    # wrong (un-joinable) task_id.
    [[ -n "$task_id" ]] || continue

    jq -nc \
      --arg event "assertion_shape" \
      --arg session_id "$session_id" \
      --arg task_id "$task_id" \
      --arg assertion_id "$assertion_id" \
      --arg shape "$shape" \
      --arg confidence "$confidence" \
      --arg ts "$ts" \
      '{event:$event, session_id:$session_id, task_id:$task_id, assertion_id:$assertion_id, shape:$shape, confidence:$confidence, timestamp:$ts}' \
      >> "$audit_path" 2>/dev/null || true

  done <<< "$(parse_contract_assertions "$contract_content")"

} || true

exit 0
