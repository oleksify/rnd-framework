#!/usr/bin/env bash
# hooks/drift-report-gate.sh — SubagentStop hook scoped to rnd-drift-detector.
# Blocks the agent from completing when the wave drift report is missing any of
# the three required sections or when the Verdict line contains an invalid value.
# Emits a gate_fired audit event regardless of outcome (pass or block).
#
# --- Verdict encoding in the tool slot ---
# The audit-event.sh helper has a fixed 3-arg signature: <event> <task_id> <tool>.
# On the pass path we encode the drift verdict by passing the tool slot as
# "drift_detector:<verdict>" (e.g. "drift_detector:NO_DRIFT"). Consumers of
# audit.jsonl that filter on the tool field use strict equality for "Write" or
# "Edit" (audit-scan.sh) or read from calibration.jsonl entirely (calibration.sh),
# so this additive suffix does not break any existing logic.
#
# Required sections:
#   ## Drift Hypothesis
#   ## Counter-evidence
#   ## Verdict
#     (first non-blank line must be one of: NO_DRIFT MINOR_DRIFT MAJOR_DRIFT RESET_RECOMMENDED)
#
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

raw="$(cat)"

agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

agent_lower="$(_lower "$agent_type")"

if [[ "$agent_lower" != *"rnd-drift-detector"* ]]; then
  exit 0
fi

session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -z "$session_dir" ]]; then
  exit 0
fi

# Locate the most recent drift report in drift/
report_path=""
if compgen -G "${session_dir}/drift/wave-*-drift-report.md" > /dev/null 2>&1; then
  report_path="$(ls -t "${session_dir}/drift/"wave-*-drift-report.md 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$report_path" ]]; then
  exit 0
fi

# Extract wave id from filename: wave-3-drift-report.md → "3"
report_base="${report_path##*/}"
wave_id="${report_base%-drift-report.md}"
wave_id="${wave_id#wave-}"

report_content="$(< "$report_path")"

# ---------------------------------------------------------------------------
# Emit gate_fired audit event — helper emitting the verdict-encoded tool slot.
# $1: verdict string to encode (e.g. NO_DRIFT) or empty string for block path.
# ---------------------------------------------------------------------------
_emit_event() {
  local verdict_suffix="$1"

  if [[ -n "${RND_DIR:-}" ]]; then
    local tool_slot
    if [[ -n "$verdict_suffix" ]]; then
      tool_slot="drift_detector:${verdict_suffix}"
    else
      tool_slot="drift_detector"
    fi

    bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
      "gate_fired" "wave-${wave_id}" "$tool_slot" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Check A: ## Drift Hypothesis heading must be present
# ---------------------------------------------------------------------------

if ! printf '%s' "$report_content" | grep -qE "^## Drift Hypothesis($|[[:space:]])"; then
  _emit_event ""

  block_msg "DRIFT REPORT GATE: drift report for wave-${wave_id} is missing the required ## Drift Hypothesis section.

Every wave-<N>-drift-report.md must include all three required sections:
  ## Drift Hypothesis     — what kind of drift (if any) was observed
  ## Counter-evidence     — evidence that contradicts or limits the hypothesis
  ## Verdict              — one of: NO_DRIFT | MINOR_DRIFT | MAJOR_DRIFT | RESET_RECOMMENDED

Report path: ${report_path}"
fi

# ---------------------------------------------------------------------------
# Check B: ## Counter-evidence heading must be present
# ---------------------------------------------------------------------------

if ! printf '%s' "$report_content" | grep -qE "^## Counter-evidence($|[[:space:]])"; then
  _emit_event ""

  block_msg "DRIFT REPORT GATE: drift report for wave-${wave_id} is missing the required ## Counter-evidence section.

Every wave-<N>-drift-report.md must include all three required sections:
  ## Drift Hypothesis     — what kind of drift (if any) was observed
  ## Counter-evidence     — evidence that contradicts or limits the hypothesis
  ## Verdict              — one of: NO_DRIFT | MINOR_DRIFT | MAJOR_DRIFT | RESET_RECOMMENDED

Report path: ${report_path}"
fi

# ---------------------------------------------------------------------------
# Check C: ## Verdict heading must be present AND first non-blank line after
# the heading must match the valid enum (case-sensitive).
# ---------------------------------------------------------------------------

if ! printf '%s' "$report_content" | grep -qE "^## Verdict($|[[:space:]])"; then
  _emit_event ""

  block_msg "DRIFT REPORT GATE: drift report for wave-${wave_id} is missing the required ## Verdict section.

Every wave-<N>-drift-report.md must include all three required sections:
  ## Drift Hypothesis     — what kind of drift (if any) was observed
  ## Counter-evidence     — evidence that contradicts or limits the hypothesis
  ## Verdict              — one of: NO_DRIFT | MINOR_DRIFT | MAJOR_DRIFT | RESET_RECOMMENDED

Report path: ${report_path}"
fi

# Extract the first non-blank line after ## Verdict
verdict_line=""
in_verdict=0

while IFS= read -r line; do
  if [[ "$line" =~ ^##[[:space:]]Verdict ]]; then
    in_verdict=1
    continue
  fi

  if [[ "$in_verdict" -eq 1 ]]; then
    if [[ "$line" =~ ^## ]]; then
      break
    fi

    # Strip leading/trailing whitespace
    trimmed="${line#"${line%%[! ]*}"}"
    trimmed="${trimmed%"${trimmed##*[! ]}"}"

    if [[ -n "$trimmed" ]]; then
      verdict_line="$trimmed"
      break
    fi
  fi
done <<< "$report_content"

valid_verdict=0
case "$verdict_line" in
  NO_DRIFT|MINOR_DRIFT|MAJOR_DRIFT|RESET_RECOMMENDED)
    valid_verdict=1
    ;;
esac

if [[ "$valid_verdict" -eq 0 ]]; then
  _emit_event ""

  block_msg "DRIFT REPORT GATE: drift report for wave-${wave_id} has an invalid or missing Verdict value.

The ## Verdict section's first non-blank line must be exactly one of (case-sensitive):
  NO_DRIFT | MINOR_DRIFT | MAJOR_DRIFT | RESET_RECOMMENDED

Found: ${verdict_line:-<empty>}

Report path: ${report_path}"
fi

# ---------------------------------------------------------------------------
# All checks passed — emit gate_fired with verdict encoded in tool slot
# ---------------------------------------------------------------------------

_emit_event "$verdict_line"

exit 0
