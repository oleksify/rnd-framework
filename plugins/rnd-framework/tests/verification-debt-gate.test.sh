#!/usr/bin/env bash
# Tests for hooks/verification-debt-gate.sh
# Usage: bash tests/verification-debt-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/verification-debt-gate.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
mkdir -p "${TMP_SESSION}/verifications"

printf '20260401-120000-abcd' > "${TMP_BASE}/.current-session"
mkdir -p "${TMP_CONFIG}/.rnd"
printf '%s' "$TMP_BASE" > "${TMP_CONFIG}/.rnd/.active-base-dir"

cleanup() {
  rm -rf "$TMP_CONFIG"
}
trap cleanup EXIT

# Helper: run the hook with CLAUDE_CONFIG_DIR pointed at the temp fixture.
run_with_session() {
  local stdin_json="$1"
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  printf '%s' "$stdin_json" \
    | env -i PATH="$PATH" HOME="$HOME" \
        CLAUDE_CONFIG_DIR="$TMP_CONFIG" \
        RND_DIR="$TMP_SESSION" \
        "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# ---------------------------------------------------------------------------
# Test 1: non-verifier agent → fast-path exit 0
# ---------------------------------------------------------------------------
printf '%s\n' '--- verification-debt-gate: non-verifier agent fast path ---'

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "rnd-builder → exit 0" 0
assert_eq "rnd-builder → empty stderr" "" "$HOOK_STDERR"

run_with_session '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'
assert_exit_code "rnd-cleanup → exit 0" 0

run_with_session '{"agent_type":"","stop_reason":"end_turn"}'
assert_exit_code "empty agent_type → exit 0" 0

# ---------------------------------------------------------------------------
# Test 2: rnd-verifier with no verification reports → exit 0 (no-op)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verification-debt-gate: no verification reports → no-op ---'

rm -f "${TMP_SESSION}/verifications/"T*-verification.md

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "no reports → exit 0" 0

# ---------------------------------------------------------------------------
# Test 3: bare PASS + non-trivial Verification Debt → exit 2 (blocks)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verification-debt-gate: bare PASS + debt section → blocks ---'

REPORT_A="${TMP_SESSION}/verifications/T1-verification.md"
printf '%s' \
  '# Verification Report: T1
## Per-Criterion Results
- [PASS] criterion one
## Overall Verdict: PASS
## Coverage Gaps
- Checked: all assertions
## Verification Debt
- gate: shellcheck
  reason: tool_unavailable
  assertion_id: M1.vdebt.hook-registered-and-validate-gre
## Feedback
No issues.
' > "$REPORT_A"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "bare PASS + debt section → exit 2" 2
assert_contains "stderr contains verification-debt-gate" "verification-debt-gate" "$HOOK_STDERR"

rm -f "$REPORT_A"

# ---------------------------------------------------------------------------
# Test 4: PASS_QUALITY_NEEDS_ITERATION + debt section → exit 0 (correctly downgraded)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verification-debt-gate: PASS_QUALITY_NEEDS_ITERATION + debt section → no block ---'

REPORT_B="${TMP_SESSION}/verifications/T1-verification.md"
printf '%s' \
  '# Verification Report: T1
## Per-Criterion Results
- [PASS] criterion one
## Overall Verdict: PASS_QUALITY_NEEDS_ITERATION
## Verification Debt
- gate: shellcheck
  reason: tool_unavailable
  assertion_id: M1.vdebt.hook-registered-and-validate-gre
## Feedback
Shellcheck unavailable; downgraded from PASS.
' > "$REPORT_B"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "PASS_QUALITY_NEEDS_ITERATION + debt → exit 0" 0
assert_eq "correctly downgraded → empty stderr" "" "$HOOK_STDERR"

rm -f "$REPORT_B"

# ---------------------------------------------------------------------------
# Test 5: report with no Verification Debt section (prose-only mention) → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verification-debt-gate: no Verification Debt section → no block ---'

REPORT_C="${TMP_SESSION}/verifications/T1-verification.md"
printf '%s' \
  '# Verification Report: T1
## Per-Criterion Results
- [PASS] criterion one
## Overall Verdict: PASS
## Coverage Gaps
- Checked: all assertions
- Could not check: shellcheck was unavailable
## Feedback
No issues.
' > "$REPORT_C"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "no debt section → exit 0" 0
assert_eq "no debt section → empty stderr" "" "$HOOK_STDERR"

rm -f "$REPORT_C"

# ---------------------------------------------------------------------------
# Test 6: NEEDS_ITERATION verdict + debt section → exit 0
# Gate only fires on bare PASS; other non-PASS verdicts must not fire.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verification-debt-gate: NEEDS_ITERATION + debt section → no block ---'

REPORT_D="${TMP_SESSION}/verifications/T1-verification.md"
printf '%s' \
  '# Verification Report: T1
## Per-Criterion Results
- [FAIL] criterion one — missing implementation
## Overall Verdict: NEEDS_ITERATION
## Verification Debt
- gate: shellcheck
  reason: tool_unavailable
  assertion_id: M1.some.assertion
## Feedback
Criterion failed.
' > "$REPORT_D"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "NEEDS_ITERATION + debt → exit 0" 0

rm -f "$REPORT_D"

# ---------------------------------------------------------------------------
# Test 7: trivial debt section (only denylist words) → exit 0 (section treated as empty)
# The gate only fires when debt section has non-trivial content.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verification-debt-gate: trivial debt section content → no block ---'

REPORT_E="${TMP_SESSION}/verifications/T1-verification.md"
printf '%s' \
  '# Verification Report: T1
## Overall Verdict: PASS
## Verification Debt
- none
## Feedback
' > "$REPORT_E"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "trivial debt (none) → exit 0" 0

rm -f "$REPORT_E"

# ---------------------------------------------------------------------------
# Test 8: no active session → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verification-debt-gate: no active session → no-op ---'

NO_SESSION_DIR="$(mktemp -d)"
rm -rf "$NO_SESSION_DIR"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$NO_SESSION_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "no active session → exit 0" 0

# ---------------------------------------------------------------------------
report
