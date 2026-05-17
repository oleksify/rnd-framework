#!/usr/bin/env bash
# hooks/verifier-case-gate.sh — SubagentStop hook.
# Blocks the rnd-verifier agent from completing when its most-recent
# T<id>-verification.md lacks both a ## Case for PASS and a ## Case for FAIL
# section, or when either section contains only trivially-empty content.
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

# Section helpers (extract_section, is_trivial_section) are provided by lib.sh.
# Trivial-content denylist for both case sections: nothing | none | n/a | no case
# Whole-line anchored after stripping bullet markers and `label: ` prefixes, so
# legitimate content like "none of the upstream APIs were called" is NOT flagged.

# ---------------------------------------------------------------------------
# Check A: ## Case for PASS heading must be present
# ---------------------------------------------------------------------------

_emit_event() {
  if [[ -n "${RND_DIR:-}" ]]; then
    bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
      "gate_fired" "$task_id" "verifier_case_symmetry" 2>/dev/null || true
  fi
}

if ! printf '%s' "$report_content" | grep -qE "^## Case for PASS($|[[:space:]])"; then
  _emit_event

  block_msg "VERIFIER CASE GATE: verification report for ${task_id} is missing the required ## Case for PASS section.

Both ## Case for PASS and ## Case for FAIL are required in every T<id>-verification.md,
regardless of the final verdict. Symmetry forces you to articulate the strongest argument
for the opposite side — even when the verdict is FAIL, you must describe what evidence
would have supported PASS, and vice versa.

Example of substantive content:
  ## Case for PASS
  The hook correctly fast-paths non-verifier agents (VAL-BEHAV-007 confirmed by exit 0
  with rnd-builder input). Section extraction matched the exact heading pattern.

  ## Case for FAIL
  (not applicable — all criteria met) OR cite what was marginal/untested.

Do NOT write only: \"nothing\", \"none\", \"n/a\", or \"no case\".

Report path: ${report_path}"
fi

# ---------------------------------------------------------------------------
# Check B: ## Case for FAIL heading must be present
# ---------------------------------------------------------------------------

if ! printf '%s' "$report_content" | grep -qE "^## Case for FAIL($|[[:space:]])"; then
  _emit_event

  block_msg "VERIFIER CASE GATE: verification report for ${task_id} is missing the required ## Case for FAIL section.

Both ## Case for PASS and ## Case for FAIL are required in every T<id>-verification.md,
regardless of the final verdict. Symmetry forces you to articulate the strongest argument
for the opposite side — even when the verdict is PASS, you must describe what evidence
would have supported FAIL, and vice versa.

Example of substantive content:
  ## Case for FAIL
  The trivial-content check uses whole-line anchoring — a partial match on \"none of X\"
  would have been a false positive. Edge case: no reports found silently exits 0.

  ## Case for PASS
  (not applicable — FAIL verdict) OR cite what was sufficient / close to passing.

Do NOT write only: \"nothing\", \"none\", \"n/a\", or \"no case\".

Report path: ${report_path}"
fi

# ---------------------------------------------------------------------------
# Check C: ## Case for PASS section must contain non-trivial content
# ---------------------------------------------------------------------------

pass_section="$(extract_section "Case for PASS" "$report_content")"

if is_trivial_section "$pass_section" "nothing" "none" "n/a" "no case"; then
  _emit_event

  block_msg "VERIFIER CASE GATE: verification report for ${task_id} contains only trivially-empty content in the ## Case for PASS section.

The section must articulate the strongest argument FOR a PASS verdict — what evidence
supports or would support passing, and why the implementation is or isn't sufficient.
Do NOT write only: \"nothing\", \"none\", \"n/a\", or \"no case\".

Instead write something like:
  ## Case for PASS
  Hook exits 0 for non-verifier agents (confirmed: rnd-builder → exit 0, empty stderr).
  Section detection correctly identifies ## Case for PASS and ## Case for FAIL headings.
  Trivial-content check rejects bare \"none\" and \"no case\" but passes \"none — all assertions ran\".

Report path: ${report_path}"
fi

# ---------------------------------------------------------------------------
# Check D: ## Case for FAIL section must contain non-trivial content
# ---------------------------------------------------------------------------

fail_section="$(extract_section "Case for FAIL" "$report_content")"

if is_trivial_section "$fail_section" "nothing" "none" "n/a" "no case"; then
  _emit_event

  block_msg "VERIFIER CASE GATE: verification report for ${task_id} contains only trivially-empty content in the ## Case for FAIL section.

The section must articulate the strongest argument FOR a FAIL verdict — what evidence
argues against passing, what was marginal, or what remained unverifiable.
Do NOT write only: \"nothing\", \"none\", \"n/a\", or \"no case\".

Instead write something like:
  ## Case for FAIL
  Live hook invocation against a running Claude Code session was not tested — could not
  confirm the gate fires during an actual SubagentStop event. Section heading regex
  requires exact spacing; a verifier using extra spaces would bypass the gate.

Report path: ${report_path}"
fi

exit 0
