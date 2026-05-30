#!/usr/bin/env bash
# hooks/calibration-producer.sh — PostToolUse Write|Edit hook.
# Path-driven calibration verdict emitter.
#
# Fires when an agent writes a .../sessions/<id>/verifications/wave-<N>-verdict-map.json
# file. Reads the verdict map, aggregates per-assertion verdicts to one per-task
# verdict via the Gate 3 rule, and appends one record per task to the slug-root
# calibration.jsonl.
#
# Verdict-map shape support:
#   Current (per-assertion-keyed): top-level keys are assertion IDs; each value
#     carries {verdict, evidence, feedback, task_id}. Group by .task_id.
#   Legacy (per-task-keyed): top-level keys ARE task IDs; each value is
#     {verdict, ...} with no inner task_id. Detected by absence of .task_id.
#
# Gate 3 collapse rule (per task):
#   any FAIL or NEEDS_ITERATION among its assertions → NEEDS_ITERATION
#   else any PASS_QUALITY_NEEDS_ITERATION → PASS_QUALITY_NEEDS_ITERATION
#   else (all PASS) → PASS
#
# Idempotency: records are appended on every fire (append-only, preserves
# time-series). The view per_shape_fail_rate.sql deduplicates latest-per-task
# via QUALIFY, mirroring self_fail_vs_verdict_gap.sql's existing pattern.
#
# Record schema (snake_case task_id — the single task-identifier casing across
# audit, verdict-map, and calibration; load-bearing for the view JOIN). The
# stats views read COALESCE(task_id, taskId) so historical camelCase records
# still join:
#   {task_id, verdict, timestamp, session_id}
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

  # Match only verifications/wave-*-verdict-map.json files under /sessions/.
  case "$file_path" in
    */sessions/*/verifications/wave-*-verdict-map.json) ;;
    *) exit 0 ;;
  esac

  # Normalize to absolute if possible (handles relative path forms — FM1).
  abs_path="$(normalize_artifact_path "$file_path")"

  # Derive session_id from the path; fall back to raw path if normalization failed.
  session_id="$(session_id_from_path "$abs_path")"

  if [[ -z "$session_id" ]]; then
    session_id="$(session_id_from_path "$file_path")"
  fi

  if [[ -z "$session_id" ]]; then
    exit 0
  fi

  # Derive slug-root calibration path from the artifact path.
  calib_path="$(calib_path_from_artifact "$abs_path")"

  if [[ -z "$calib_path" ]]; then
    calib_path="$(calib_path_from_artifact "$file_path")"
  fi

  if [[ -z "$calib_path" ]]; then
    exit 0
  fi

  # Read the verdict map from disk (the file that just triggered this hook).
  verdict_map_file="$abs_path"
  if [[ ! -f "$verdict_map_file" ]]; then
    verdict_map_file="$file_path"
  fi
  if [[ ! -f "$verdict_map_file" ]]; then
    exit 0
  fi

  map_json="$(< "$verdict_map_file")"
  if [[ -z "$map_json" ]]; then
    exit 0
  fi

  ts="$(iso_timestamp)"

  # Detect format: per-assertion (current) vs per-task (legacy).
  # Current maps have at least one entry whose .value has a .task_id field.
  # We detect by checking whether the first entry's value has task_id.
  is_per_assertion="$(printf '%s' "$map_json" | jq -r '
    (to_entries | first | .value | has("task_id")) // false
  ' 2>/dev/null || echo "false")"

  # Ensure the calibration dir exists (slug root must be writable).
  mkdir -p "$(dirname "$calib_path")" 2>/dev/null || true

  if [[ "$is_per_assertion" == "true" ]]; then
    # Current format: group by task_id, then apply Gate 3 collapse.
    # jq walks the map, groups per-assertion entries by task_id, collapses.
    printf '%s' "$map_json" | jq -rc \
      --arg ts "$ts" \
      --arg session_id "$session_id" \
      '
      # Collect all {task_id, verdict} pairs from the assertion values.
      [ to_entries[] | {task_id: .value.task_id, verdict: .value.verdict} ]
      | group_by(.task_id)
      | .[]
      | {
          task_id: .[0].task_id,
          verdicts: [ .[] | .verdict ]
        }
      | {
          task_id: .task_id,
          verdict: (
            if (.verdicts | any(. == "FAIL" or . == "NEEDS_ITERATION"))
            then "NEEDS_ITERATION"
            elif (.verdicts | any(. == "PASS_QUALITY_NEEDS_ITERATION"))
            then "PASS_QUALITY_NEEDS_ITERATION"
            else "PASS"
            end
          ),
          timestamp: $ts,
          session_id: $session_id
        }
      ' 2>/dev/null >> "$calib_path" || true

  else
    # Legacy format: top-level keys are task IDs; value carries the single verdict.
    # No aggregation needed — one record per key.
    printf '%s' "$map_json" | jq -rc \
      --arg ts "$ts" \
      --arg session_id "$session_id" \
      '
      to_entries[]
      | {
          task_id:    .key,
          verdict:    .value.verdict,
          timestamp:  $ts,
          session_id: $session_id
        }
      ' 2>/dev/null >> "$calib_path" || true
  fi

} || true

exit 0
