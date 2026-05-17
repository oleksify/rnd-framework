#!/usr/bin/env bash
# hooks/coverage-gaps-gate.sh — SubagentStop hook.
# Blocks the rnd-verifier agent from completing when its most-recent
# T<id>-verification.md lacks a ## Coverage Gaps section or contains only
# trivially-empty content in that section.
# Exits 2 (block) on violation; exits 0 (no-opinion) for all other agents or
# when no active session / verification report is found.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

raw="$(cat)"

agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

agent_lower="$(_lower "$agent_type")"

if [[ "$agent_lower" != *"rnd-verifier"* ]]; then
  exit 0
fi

session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -z "$session_dir" ]]; then
  exit 0
fi

# Locate the most recent verification report in verifications/
reports=()
if compgen -G "${session_dir}/verifications/T*-verification.md" > /dev/null 2>&1; then
  while IFS= read -r f; do
    reports+=("$f")
  done < <(ls -t "${session_dir}/verifications/"T*-verification.md 2>/dev/null)
fi

if [[ "${#reports[@]}" -eq 0 ]]; then
  exit 0
fi

report_path="${reports[0]}"

# Extract task ID from filename: T1-verification.md → T1
report_base="${report_path##*/}"
task_id="${report_base%-verification.md}"

report_content="$(< "$report_path")"

# ---------------------------------------------------------------------------
# Check A: ## Coverage Gaps heading must be present
# ---------------------------------------------------------------------------

if ! printf '%s' "$report_content" | grep -q "^## Coverage Gaps"; then
  # Emit gateFired audit event before blocking
  if [[ -n "${RND_DIR:-}" ]]; then
    bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
      "gate_fired" "$task_id" "coverage_gaps_gate" 2>/dev/null || true
  fi

  block_msg "coverage-gaps-gate: verification report for ${task_id} is missing the required ## Coverage Gaps section.

Every T<id>-verification.md must include a ## Coverage Gaps section placed between
## Overall Verdict and ## Feedback, with:
  - Checked: [list of VAL assertions and code paths you verified]
  - Couldn't check: [specific item] — [specific reason]

Do NOT write trivially-empty content like \"nothing\", \"none\", \"n/a\",
\"all checks ran\", or \"no gaps\" as the entire section content.

Report path: ${report_path}"
fi

# ---------------------------------------------------------------------------
# Check B: Section must contain non-trivial content
#
# Trivial-content denylist (whole-line anchored to avoid false positives):
#   nothing | none | n/a | all checks ran | no gaps
#
# Whole-line matching prevents triggering on legitimate content such as:
#   "Couldn't check: none of the upstream APIs were reachable"
# because that line contains additional words beyond the bare trivial term.
# ---------------------------------------------------------------------------

# Extract the section content: lines after ## Coverage Gaps until the next ## heading
section_content=""
in_section=0

while IFS= read -r line; do
  if [[ "$line" =~ ^##[[:space:]]Coverage[[:space:]]Gaps ]]; then
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

# Check whether all non-empty lines in the section are trivially-empty
trivial_only=1
has_any_content=0

while IFS= read -r line; do
  # Skip blank lines
  line_stripped="${line#"${line%%[! ]*}"}"
  if [[ -z "$line_stripped" ]]; then
    continue
  fi

  has_any_content=1

  # Whole-line match against trivial terms (case-insensitive)
  # Strip leading bullet markers before matching
  stripped="${line_stripped#-}"
  stripped="${stripped#\*}"
  stripped="${stripped# }"

  line_lower="$(_lower "$stripped")"

  # Match exact trivial values only (anchored — no additional words allowed).
  # Strip any sub-bullet label prefix up to and including the first colon+space
  # (e.g. "Checked: " or "Couldn't check: ") before testing, so both
  # "- Checked: nothing" and "- nothing" match the trivial denylist.
  # This does NOT match "Couldn't check: none of the upstream APIs were reachable"
  # because after stripping the prefix "none of the upstream APIs were reachable"
  # does not equal any trivial term.
  if [[ "$line_lower" == *": "* ]]; then
    sub_value="${line_lower#*: }"
  else
    sub_value="$line_lower"
  fi

  if [[ "$sub_value" == "nothing" ]] || \
     [[ "$sub_value" == "none" ]] || \
     [[ "$sub_value" == "n/a" ]] || \
     [[ "$sub_value" == "all checks ran" ]] || \
     [[ "$sub_value" == "no gaps" ]]; then
    # This line is trivial — continue checking the rest
    true
  else
    # Found a non-trivial line — section is meaningful
    trivial_only=0
    break
  fi
done <<< "$section_content"

if [[ "$has_any_content" -eq 1 && "$trivial_only" -eq 1 ]]; then
  # Emit gateFired audit event before blocking
  if [[ -n "${RND_DIR:-}" ]]; then
    bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
      "gate_fired" "$task_id" "coverage_gaps_gate" 2>/dev/null || true
  fi

  block_msg "coverage-gaps-gate: verification report for ${task_id} contains only trivially-empty content in the ## Coverage Gaps section.

The section must describe WHAT was checked and WHY specific items could not be checked.
Do NOT write only: \"nothing\", \"none\", \"n/a\", \"all checks ran\", or \"no gaps\".

Instead write something like:
  - Checked: VAL-COVGAPS-001 (grep output matched), all 4 test cases ran, hook parse logic traced line-by-line
  - Couldn't check: live hook invocation against a running Claude Code session — requires a live agent spawn

If everything was verifiable, write:
  - Couldn't check: none — all VAL assertions and experiment tests ran successfully against the implementation.

Report path: ${report_path}"
fi

exit 0
