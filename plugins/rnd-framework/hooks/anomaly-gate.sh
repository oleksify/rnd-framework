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

if printf '%s' "$report_content" | grep -qE "^## Anomalies($|[[:space:]])"; then
  in_section=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]Anomalies ]]; then
      in_section=1
      continue
    fi

    if [[ "$in_section" -eq 1 ]]; then
      if [[ "$line" =~ ^## ]]; then
        break
      fi

      # Case-sensitive: schema requires "Source:" (structured field)
      if [[ "$line" == *"Source:"* ]]; then
        check_a_passed=1
        break
      fi
    fi
  done <<< "$report_content"
fi

# ---------------------------------------------------------------------------
# Check B: ## No-Finding Rationale heading present AND content ≥200 chars
#          AND content is not solely trivial-denylist
#
# Trivial-content denylist (whole-bullet anchored after stripping markers):
#   everything checks out | all valid | nothing unusual | looks good | no issues found
# ---------------------------------------------------------------------------

check_b_passed=0

if printf '%s' "$report_content" | grep -qE "^## No-Finding Rationale($|[[:space:]])"; then
  section_content=""
  in_section=0

  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]No-Finding[[:space:]]Rationale ]]; then
      in_section=1
      continue
    fi

    if [[ "$in_section" -eq 1 ]]; then
      if [[ "$line" =~ ^## ]]; then
        break
      fi

      section_content="${section_content}${line}
"
    fi
  done <<< "$report_content"

  # Must be at least 200 chars of total content
  content_length="${#section_content}"

  if [[ "$content_length" -ge 200 ]]; then
    # Check whether all non-empty lines are trivially-empty
    trivial_only=1
    has_any_content=0

    while IFS= read -r line; do
      # Skip blank lines
      line_stripped="${line#"${line%%[! ]*}"}"
      if [[ -z "$line_stripped" ]]; then
        continue
      fi

      has_any_content=1

      # Strip leading bullet markers before matching
      stripped="${line_stripped#-}"
      stripped="${stripped#\*}"
      stripped="${stripped# }"

      line_lower="$(_lower "$stripped")"

      # Strip any sub-bullet label prefix (e.g. "label: ") before testing
      if [[ "$line_lower" == *": "* ]]; then
        sub_value="${line_lower#*: }"
      else
        sub_value="$line_lower"
      fi

      if [[ "$sub_value" != "everything checks out" ]] && \
         [[ "$sub_value" != "all valid" ]] && \
         [[ "$sub_value" != "nothing unusual" ]] && \
         [[ "$sub_value" != "looks good" ]] && \
         [[ "$sub_value" != "no issues found" ]]; then
        trivial_only=0
        break
      fi
    done <<< "$section_content"

    if [[ "$has_any_content" -eq 0 ]] || [[ "$trivial_only" -eq 0 ]]; then
      check_b_passed=1
    fi
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
