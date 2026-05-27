#!/usr/bin/env bash
# hooks/self-assessment-producer.sh — PostToolUse Write|Edit hook.
# Path-driven builder_self_assessment emitter.
#
# Fires when an agent writes a .../sessions/<id>/builds/<task>-self-assessment.md
# file. Derives session_id and task_id from the file path (never from
# active_session_dir or .current-session), infers PASS/FAIL from the file
# content, and appends one builder_self_assessment record to the session
# audit.jsonl co-located with the builds/ directory.
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

  # Match: path must contain /sessions/ and end with -self-assessment.md
  # under a builds/ directory.
  case "$file_path" in
    */sessions/*/builds/*-self-assessment.md) ;;
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

  # Derive task_id from filename: strip the directory prefix and suffix.
  filename="${abs_path##*/}"
  task_id="${filename%-self-assessment.md}"

  # Compute the session dir (parent of builds/).
  builds_dir="${abs_path%/*}"
  session_dir="${builds_dir%/*}"

  audit_path="${session_dir}/audit.jsonl"

  # Read the file to infer self_verdict.
  assessment_content=""
  if [[ -f "$abs_path" ]]; then
    assessment_content="$(< "$abs_path")"
  fi

  # Infer self_verdict:
  # FAIL: full-template form (has section headings, MEDIUM/LOW confidence).
  # PASS: minimal one-liner form (none of the above markers present).
  self_verdict="PASS"

  if printf '%s' "$assessment_content" | grep -q "^## Confidence per criterion"; then
    self_verdict="FAIL"
  elif printf '%s' "$assessment_content" | grep -q "^## Uncertainties"; then
    self_verdict="FAIL"
  elif printf '%s' "$assessment_content" | grep -q "^## Deviations"; then
    self_verdict="FAIL"
  elif printf '%s' "$assessment_content" | grep -qiE '(^|[^A-Za-z])(MEDIUM|LOW)([^A-Za-z]|$)'; then
    # Portable ERE (BSD + GNU) + non-alphanumeric boundaries: matches the
    # MEDIUM/LOW confidence tokens the template emits, without false-matching
    # ordinary words that merely contain "low" (follows, below, allow, flow).
    self_verdict="FAIL"
  fi

  ts="$(iso_timestamp)"

  jq -nc \
    --arg event "builder_self_assessment" \
    --arg session_id "$session_id" \
    --arg task_id "$task_id" \
    --arg self_verdict "$self_verdict" \
    --arg ts "$ts" \
    '{event:$event, session_id:$session_id, task_id:$task_id, self_verdict:$self_verdict, timestamp:$ts}' \
    >> "$audit_path" 2>/dev/null || true

} || true

exit 0
