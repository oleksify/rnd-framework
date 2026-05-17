#!/usr/bin/env bash
# hooks/anomaly-gate.sh — SubagentStop hook.
# Blocks the rnd-reality-auditor agent from completing when its most-recent
# T<id>-reality-report.md lacks either a sourced ## Anomalies section (with
# at least one "Source:" bullet) or a substantive ## No-Finding Rationale
# section (≥200 chars, non-trivial content).
# Exits 2 (block) on violation; exits 0 (no-opinion) for all other agents or
# when no active session / reality report is found.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

raw="$(cat)"

agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

agent_lower="$(_lower "$agent_type")"

if [[ "$agent_lower" != *"rnd-reality-auditor"* ]]; then
  exit 0
fi

session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -z "$session_dir" ]]; then
  exit 0
fi

# Locate the most recent reality report in reality/
reports=()
if compgen -G "${session_dir}/reality/T*-reality-report.md" > /dev/null 2>&1; then
  while IFS= read -r f; do
    reports+=("$f")
  done < <(ls -t "${session_dir}/reality/"T*-reality-report.md 2>/dev/null)
fi

if [[ "${#reports[@]}" -eq 0 ]]; then
  exit 0
fi

report_path="${reports[0]}"

# Extract task ID from filename: T1-reality-report.md → T1
report_base="${report_path##*/}"
task_id="${report_base%-reality-report.md}"

report_content="$(< "$report_path")"

# ---------------------------------------------------------------------------
# Check A: ## Anomalies heading present AND ≥1 bullet contains "Source:"
# ---------------------------------------------------------------------------

check_a_passed=0

anomalies_section="$(extract_section "Anomalies" "$report_content")"

if [[ -n "$anomalies_section" ]] && printf '%s' "$anomalies_section" | grep -q "Source:"; then
  check_a_passed=1
fi

# ---------------------------------------------------------------------------
# Check B: ## No-Finding Rationale heading present AND content ≥200 chars
#          AND content is not solely trivial-denylist
#
# Trivial-content denylist (whole-bullet anchored after stripping markers):
#   everything checks out | all valid | nothing unusual | looks good | no issues found
# ---------------------------------------------------------------------------

check_b_passed=0

rationale_section="$(extract_section "No-Finding Rationale" "$report_content")"

if [[ "${#rationale_section}" -ge 200 ]]; then
  if ! is_trivial_section "$rationale_section" \
       "everything checks out" "all valid" "nothing unusual" "looks good" "no issues found"; then
    check_b_passed=1
  fi
fi

# ---------------------------------------------------------------------------
# Block when BOTH checks fail
# ---------------------------------------------------------------------------

if [[ "$check_a_passed" -eq 1 ]] || [[ "$check_b_passed" -eq 1 ]]; then
  exit 0
fi

# Emit gate_fired audit event before blocking
if [[ -n "${RND_DIR:-}" ]]; then
  bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
    "gate_fired" "$task_id" "anomaly_gate" 2>/dev/null || true
fi

block_msg "ANOMALY GATE: reality report for ${task_id} must include either a sourced ## Anomalies section or a substantive ## No-Finding Rationale section.

Required format — choose ONE of:

Option 1: ## Anomalies section with at least one sourced finding
  ## Anomalies
  - Source: \`path/to/file:line\` — description of anomaly found

Option 2: ## No-Finding Rationale section (≥200 chars, non-trivial)
  ## No-Finding Rationale
  All N external interactions were validated by running adversarial experiments.
  Each hypothesis was tested against the live system. No schema mismatches,
  shape errors, or missing variables were detected. [Continue with specifics...]

Do NOT write only trivially-empty content like \"everything checks out\",
\"all valid\", \"nothing unusual\", \"looks good\", or \"no issues found\".

Report path: ${report_path}"
