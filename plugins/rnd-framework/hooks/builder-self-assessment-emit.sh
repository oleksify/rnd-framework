#!/usr/bin/env bash
# hooks/builder-self-assessment-emit.sh — SubagentStop hook.
# Emits a structured builder self-verdict to audit.jsonl at builder SubagentStop.
# Reads the most-recently-modified builds/*-self-assessment.md in the active
# session, infers PASS (minimal one-liner form) or FAIL (full template), and
# appends one JSON line with event="builder_self_assessment".
# Non-blocking: always exits 0 regardless of internal errors.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

raw="$(cat)"

agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

agent_lower="$(_lower "$agent_type")"

if [[ "$agent_lower" != *"rnd-builder"* ]]; then
  exit 0
fi

session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -z "$session_dir" ]]; then
  exit 0
fi

# Wrap everything from here in a subshell so any error exits 0 (non-blocking).
{
  builds_dir="${session_dir}/builds"

  # Locate the most-recently-modified self-assessment file.
  assessment_path=""
  if compgen -G "${builds_dir}/"*-self-assessment.md > /dev/null 2>&1; then
    assessment_path="$(ls -t "${builds_dir}/"*-self-assessment.md 2>/dev/null | head -1)"
  fi

  if [[ -z "$assessment_path" ]] || [[ ! -f "$assessment_path" ]]; then
    exit 0
  fi

  # Extract task_id from filename: strip directory and "-self-assessment.md" suffix.
  assessment_base="${assessment_path##*/}"
  task_id="${assessment_base%-self-assessment.md}"

  # Extract session_id from the session directory path (last path component).
  session_id="${session_dir##*/}"

  assessment_content="$(< "$assessment_path")"

  # Infer self_verdict from the self-assessment form:
  # PASS: minimal one-liner form (no section headings, no MEDIUM/LOW keywords)
  # FAIL: full template (contains ## Confidence per criterion, ## Uncertainties,
  #       ## Deviations, or any MEDIUM / LOW confidence rating)
  self_verdict="PASS"

  if printf '%s' "$assessment_content" | grep -q "^## Confidence per criterion"; then
    self_verdict="FAIL"
  elif printf '%s' "$assessment_content" | grep -q "^## Uncertainties"; then
    self_verdict="FAIL"
  elif printf '%s' "$assessment_content" | grep -q "^## Deviations"; then
    self_verdict="FAIL"
  elif printf '%s' "$assessment_content" | grep -qi "MEDIUM\|LOW"; then
    self_verdict="FAIL"
  fi

  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # Append the audit event line. Use jq to guarantee valid JSON escaping.
  jq -nc \
    --arg event "builder_self_assessment" \
    --arg session_id "$session_id" \
    --arg task_id "$task_id" \
    --arg self_verdict "$self_verdict" \
    --arg ts "$ts" \
    '{event:$event, session_id:$session_id, task_id:$task_id, self_verdict:$self_verdict, timestamp:$ts}' \
    >> "${session_dir}/audit.jsonl" 2>/dev/null || true

} || true

exit 0
