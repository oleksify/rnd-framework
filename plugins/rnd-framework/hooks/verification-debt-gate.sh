#!/usr/bin/env bash
# hooks/verification-debt-gate.sh — SubagentStop hook.
# Blocks the rnd-verifier agent from completing when its most-recent
# T<id>-verification.md contains a non-trivial ## Verification Debt section
# AND the Overall Verdict is the bare PASS (not PASS_QUALITY_NEEDS_ITERATION).
# A correctly-downgraded PASS_QUALITY_NEEDS_ITERATION must NOT fire this gate.
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
# Check A: ## Verification Debt section must be present and non-trivial
# ---------------------------------------------------------------------------

if ! printf '%s' "$report_content" | grep -q "^## Verification Debt"; then
  exit 0
fi

section_content="$(extract_section "Verification Debt" "$report_content")"

if is_trivial_section "$section_content" "none" "n/a" "no debt" "nothing"; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Check B: Overall Verdict must be the bare PASS (not PASS_QUALITY_NEEDS_ITERATION)
# A correctly-downgraded verdict does not fire the gate.
# ---------------------------------------------------------------------------

# Match the bare PASS verdict line — with or without ## heading prefix.
# Must NOT match PASS_QUALITY_NEEDS_ITERATION (that is the correctly-downgraded form).
if ! printf '%s' "$report_content" | grep -qE "^(## )?Overall Verdict: PASS$"; then
  exit 0
fi

# Both conditions met: non-trivial debt section AND bare PASS verdict.
# Emit gate_fired audit event then block.
if [[ -n "${RND_DIR:-}" ]]; then
  bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
    "gate_fired" "$task_id" "verification_debt_gate" 2>/dev/null || true
fi

block_msg "verification-debt-gate: verification report for ${task_id} has a ## Verification Debt section but Overall Verdict is bare PASS.

When a pre-reg-named quality gate (linter, test runner, checker) was unavailable,
the verifier must downgrade the verdict one tier:
  PASS → PASS_QUALITY_NEEDS_ITERATION

The ## Verification Debt section was written, which is correct — but the verdict
must also be downgraded. Update the Overall Verdict line to:
  Overall Verdict: PASS_QUALITY_NEEDS_ITERATION

And emit a gate_fired audit event via:
  lib/audit-event.sh gate_fired <task_id> verification_debt_gate <assertion_id>

Report path: ${report_path}"
