#!/usr/bin/env bash
# hooks/coverage-gaps-gate.sh — SubagentStop hook.
# Blocks the rnd-verifier agent from completing when its most-recent
# T<id>-verification.md lacks a ## Coverage Gaps section or contains only
# trivially-empty content in that section.
# The section-presence check is scope-agnostic: it fires whether the body
# lists a single overall summary or enumerates per-assertion coverage detail.
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
# ---------------------------------------------------------------------------

section_content="$(extract_section "Coverage Gaps" "$report_content")"

if is_trivial_section "$section_content" "nothing" "none" "n/a" "all checks ran" "no gaps"; then
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
