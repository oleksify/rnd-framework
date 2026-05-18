#!/usr/bin/env bash
# inline-verify.sh — Run mechanical Evidence commands from the Validation Contract
# in-process, producing a verdict map identical in shape to a spawned verifier's
# wave-N-verdict-map.json. Only valid when all tasks in the wave carry
# `Verification level: inline`.
#
# Usage:
#   inline-verify.sh <plan.md-path> <wave-number>
#
# Writes verdict map to $RND_DIR/verifications/wave-<N>-verdict-map.json and
# prints the path to stderr. Appends one verifier_spawn_avoided audit event
# per task.
#
# Exit codes:
#   0  Verdict map written (task-level verdicts may be FAIL — check the JSON).
#   1  Usage error, plan.md not found, or RND_DIR unset.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_usage() {
  printf 'Usage: inline-verify.sh <plan.md-path> <wave-number>\n\n'
  printf 'Runs mechanical Evidence commands from the Validation Contract for every\n'
  printf 'task in the wave and writes a verdict map JSON to:\n'
  printf '  $RND_DIR/verifications/wave-<N>-verdict-map.json\n\n'
  printf 'Requires RND_DIR to be set.\n'
}

if [[ "${1:-}" == "--help" ]]; then
  _usage
  exit 0
fi

if [[ $# -lt 2 ]]; then
  printf 'inline-verify.sh: expected <plan.md-path> <wave-number>, got %d args\n' "$#" >&2
  _usage >&2
  exit 1
fi

_PLAN="$1"
_WAVE="$2"

if [[ ! -f "$_PLAN" ]]; then
  printf 'inline-verify.sh: plan.md not found: %s\n' "$_PLAN" >&2
  exit 1
fi

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'inline-verify.sh: RND_DIR is not set\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# _wave_task_ids <plan_path> <wave_num>
# Prints space-separated task numeric IDs (without the "T" prefix) for the
# given wave number. Reads the "## Task Tree" section of plan.md.
# Wave header formats accepted:
#   "- Roadmap Wave N " or "- Wave N "
# ---------------------------------------------------------------------------
_wave_task_ids() {
  awk -v wave="$2" '
    /^## Task Tree/  { in_tree = 1; next }
    in_tree && /^## / { exit }

    in_tree {
      if ($0 ~ /^- (Roadmap )?Wave [0-9]/) {
        head = $0
        sub(/.*Wave /, "", head)
        sub(/[^0-9].*/, "", head)
        in_wave = (head + 0 == wave + 0)
        next
      }
      if (in_wave) {
        line = $0
        while (match(line, /\*\*T[0-9]+\*\*/) > 0) {
          # RSTART+2 skips "**", RSTART+3 skips "**T"; RLENGTH-5 = total - "**T" - "**"
          print substr(line, RSTART + 3, RLENGTH - 5)
          line = substr(line, RSTART + RLENGTH)
        }
      }
    }
  ' "$1"
}

# ---------------------------------------------------------------------------
# _prereg_field <plan_path> <task_id_num> <field_name>
# Extracts a single-line field value from the task's pre-reg fenced block.
# Example: _prereg_field plan.md 8 "Verification level"  → "inline"
# ---------------------------------------------------------------------------
_prereg_field() {
  local plan_path="$1" task_num="$2" field="$3"
  awk -v num="$task_num" -v field="$field" '
    /^### Task T/ {
      in_task = ($0 ~ ("^### Task T" num " "))
      in_block = 0
    }
    in_task && /^```$/ {
      if (!in_block) { in_block = 1; next }
      in_task = 0; in_block = 0
    }
    in_task && in_block && index($0, field ": ") == 1 {
      val = substr($0, length(field ": ") + 1)
      print val
      exit
    }
  ' "$plan_path"
}

# ---------------------------------------------------------------------------
# _val_evidence <plan_path> <val_id>
# Extracts the backtick-quoted command from the Evidence line of a VAL block.
# Example: _val_evidence plan.md "VAL-VACT-001"  → "bash tests/foo.test.sh"
# ---------------------------------------------------------------------------
_val_evidence() {
  local plan_path="$1" val_id="$2"
  awk -v vid="$val_id" '
    /^## Validation Contract/ { in_contract = 1; next }
    in_contract && /^## /     { exit }
    in_contract {
      if ($0 ~ ("^#### " vid ":")) { in_val = 1; next }
      if (in_val && /^#### VAL-/) { exit }
      if (in_val && /^Evidence:/) {
        line = $0
        if (match(line, /`([^`]+)`/)) {
          print substr(line, RSTART + 1, RLENGTH - 2)
        }
        exit
      }
    }
  ' "$plan_path"
}

# ---------------------------------------------------------------------------
# _run_evidence_cmd <cmd> <val_id>
# Runs the Evidence command via bash -c and returns:
#   "PASS" or "FAIL" on the first line of stdout.
# The Evidence summary text is on the second line.
# ---------------------------------------------------------------------------
_run_evidence_cmd() {
  local cmd="$1" val_id="$2"
  local exit_code=0
  local output=""
  output="$(bash -c "$cmd" 2>&1)" || exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    printf 'PASS\n%s: exit 0\n' "$val_id"
  else
    local first_line
    first_line="$(printf '%s' "$output" | head -1)"
    printf 'FAIL\n%s: exit %d — %s\n' "$val_id" "$exit_code" "$first_line"
  fi
}

# ---------------------------------------------------------------------------
# _verify_task <plan_path> <task_num>
# Processes one task: runs all Evidence commands for its VAL assertions,
# emits a verifier_spawn_avoided audit event, and prints a JSON object:
#   {"verdict":"PASS"|"FAIL","evidence":[...],"feedback":""}
# ---------------------------------------------------------------------------
_verify_task() {
  local plan_path="$1" task_num="$2"
  local task_id="T${task_num}"

  # Emit audit event — spawn avoided for this task
  RND_DIR="$RND_DIR" bash "${_SCRIPT_DIR}/audit-event.sh" \
    "verifier_spawn_avoided" "$task_id" "inline" 2>/dev/null || true

  local fulfills_raw
  fulfills_raw="$(_prereg_field "$plan_path" "$task_num" "fulfills")"

  if [[ -z "$fulfills_raw" ]]; then
    jq -n '{
      verdict: "FAIL",
      evidence: ["No fulfills field found — no VAL assertions to run"],
      feedback: "Pre-reg is missing the fulfills field."
    }'
    return
  fi

  # Parse VAL IDs from: [VAL-VACT-001, VAL-VACT-002, VAL-VACT-004]
  local val_ids
  val_ids="$(printf '%s' "$fulfills_raw" | tr -d '[]' | tr ',' '\n' | tr -d ' ')"

  local evidence_items=()
  local all_pass=true
  local feedback_parts=()

  while IFS= read -r val_id; do
    [[ -z "$val_id" ]] && continue

    local evidence_cmd
    evidence_cmd="$(_val_evidence "$plan_path" "$val_id")"

    if [[ -z "$evidence_cmd" ]]; then
      evidence_items+=("${val_id}: Evidence command not found in Validation Contract")
      all_pass=false
      feedback_parts+=("${val_id}: no Evidence command found.")
      continue
    fi

    local run_output status detail
    run_output="$(_run_evidence_cmd "$evidence_cmd" "$val_id")"
    status="$(printf '%s' "$run_output" | head -1)"
    detail="$(printf '%s' "$run_output" | tail -1)"

    evidence_items+=("$detail")

    if [[ "$status" != "PASS" ]]; then
      all_pass=false
      feedback_parts+=("$detail")
    fi
  done <<< "$val_ids"

  # Build evidence JSON array
  local evidence_json
  evidence_json="$(printf '%s\n' "${evidence_items[@]}" | jq -R . | jq -s '.')"

  local verdict feedback
  if [[ "$all_pass" == true ]]; then
    verdict="PASS"
    feedback=""
  else
    verdict="FAIL"
    feedback="$(printf '%s ' "${feedback_parts[@]}")"
    feedback="${feedback% }"
  fi

  jq -n \
    --arg verdict "$verdict" \
    --argjson evidence "$evidence_json" \
    --arg feedback "$feedback" \
    '{"verdict":$verdict,"evidence":$evidence,"feedback":$feedback}'
}

# ---------------------------------------------------------------------------
# Main: collect tasks, verify each, assemble and write verdict map
# ---------------------------------------------------------------------------

_VERIF_DIR="${RND_DIR}/verifications"
mkdir -p "$_VERIF_DIR"

_VERDICT_MAP="{}"

while IFS= read -r _TASK_NUM; do
  [[ -z "$_TASK_NUM" ]] && continue
  _TASK_VERDICT="$(_verify_task "$_PLAN" "$_TASK_NUM")"
  _VERDICT_MAP="$(
    printf '%s' "$_VERDICT_MAP" | \
    jq --arg tid "T${_TASK_NUM}" --argjson v "$_TASK_VERDICT" \
      '. + {($tid): $v}'
  )"
done < <(_wave_task_ids "$_PLAN" "$_WAVE")

if [[ "$_VERDICT_MAP" == "{}" ]]; then
  printf 'inline-verify.sh: no tasks found for wave %s\n' "$_WAVE" >&2
  exit 1
fi

_VERDICT_MAP_PATH="${_VERIF_DIR}/wave-${_WAVE}-verdict-map.json"
printf '%s\n' "$_VERDICT_MAP" | jq '.' > "$_VERDICT_MAP_PATH"

printf 'inline-verify.sh: wave %s verdict map written to %s\n' "$_WAVE" "$_VERDICT_MAP_PATH" >&2
