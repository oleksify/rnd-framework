#!/usr/bin/env bash
# Tests for hooks/verifier-case-gate.sh
# Usage: bash tests/verifier-case-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/verifier-case-gate.sh"

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
        "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# ---------------------------------------------------------------------------
# Test 1: non-verifier agent → fast-path exit 0 (VAL-BEHAV-007)
# ---------------------------------------------------------------------------
printf '%s\n' '--- verifier-case-gate: non-verifier agent fast path ---'

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
printf '\n%s\n' '--- verifier-case-gate: no verification reports → no-op ---'

rm -f "${TMP_SESSION}/verifications/"T*-verification.md

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "no reports → exit 0" 0

# ---------------------------------------------------------------------------
# Test 3: missing ## Case for PASS → exit 2 (VAL-BEHAV-008)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: missing ## Case for PASS blocks ---'

REPORT_A="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Per-Criterion Results\n### Correctness Tier\n- [PASS] criterion one — evidence\n## Overall Verdict: PASS\n## Case for FAIL\nThe trivial-content check uses whole-line anchoring to avoid false positives.\n## Coverage Gaps\n- Checked: all assertions\n- Couldn'"'"'t check: live invocation\n## Feedback\nNo issues.\n' \
  > "$REPORT_A"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "missing Case for PASS → exit 2" 2
assert_contains "stderr contains VERIFIER CASE GATE" "VERIFIER CASE GATE" "$HOOK_STDERR"
assert_contains "stderr mentions Case for PASS" "Case for PASS" "$HOOK_STDERR"

rm -f "$REPORT_A"

# ---------------------------------------------------------------------------
# Test 4: missing ## Case for FAIL → exit 2 (VAL-BEHAV-008)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: missing ## Case for FAIL blocks ---'

REPORT_B="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Per-Criterion Results\n### Correctness Tier\n- [PASS] criterion one — evidence\n## Overall Verdict: PASS\n## Case for PASS\nHook exits 0 for non-verifier agents; section detection correct.\n## Coverage Gaps\n- Checked: all assertions\n- Couldn'"'"'t check: live invocation\n## Feedback\nNo issues.\n' \
  > "$REPORT_B"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "missing Case for FAIL → exit 2" 2
assert_contains "stderr contains VERIFIER CASE GATE" "VERIFIER CASE GATE" "$HOOK_STDERR"
assert_contains "stderr mentions Case for FAIL" "Case for FAIL" "$HOOK_STDERR"

rm -f "$REPORT_B"

# ---------------------------------------------------------------------------
# Test 5a: trivial PASS section ("nothing") → exit 2 (VAL-BEHAV-009)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: trivial Case for PASS content blocks ---'

REPORT_C="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS\n## Case for PASS\n- nothing\n## Case for FAIL\nThe hook could miss reports if the filesystem ordering changes.\n## Coverage Gaps\n- Checked: all\n- Couldn'"'"'t check: live spawn\n## Feedback\n' \
  > "$REPORT_C"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "trivial Case for PASS → exit 2" 2
assert_contains "stderr contains VERIFIER CASE GATE" "VERIFIER CASE GATE" "$HOOK_STDERR"

rm -f "$REPORT_C"

# ---------------------------------------------------------------------------
# Test 5b: trivial FAIL section ("no case") → exit 2 (VAL-BEHAV-009)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: trivial Case for FAIL content blocks ---'

REPORT_D="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS\n## Case for PASS\nHook exits 0 for non-verifier agents (confirmed: rnd-builder → exit 0).\n## Case for FAIL\n- no case\n## Coverage Gaps\n- Checked: all\n- Couldn'"'"'t check: live spawn\n## Feedback\n' \
  > "$REPORT_D"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "trivial Case for FAIL → exit 2" 2
assert_contains "stderr contains VERIFIER CASE GATE" "VERIFIER CASE GATE" "$HOOK_STDERR"

rm -f "$REPORT_D"

# ---------------------------------------------------------------------------
# Test 5c: trivial with label prefix ("Evidence: none") → exit 2 (VAL-BEHAV-009)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: trivial with label prefix blocks ---'

REPORT_E="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: FAIL\n## Case for PASS\n- Evidence: none\n## Case for FAIL\nAll correctness criteria failed — implementation missing.\n## Coverage Gaps\n- Checked: file existence\n- Couldn'"'"'t check: runtime behavior\n## Feedback\nImplementation missing.\n' \
  > "$REPORT_E"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "trivial label-prefix none → exit 2" 2

rm -f "$REPORT_E"

# ---------------------------------------------------------------------------
# Test 6: both sections present with substantive content → exit 0 (VAL-BEHAV-011)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: both sections substantive → passes ---'

REPORT_F="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Per-Criterion Results\n### Correctness Tier\n- [PASS] criterion one — evidence\n## Overall Verdict: PASS\n## Case for PASS\nHook exits 0 for non-verifier agents (confirmed: rnd-builder → exit 0, empty stderr).\nSection detection correctly identifies ## Case for PASS and ## Case for FAIL headings.\n## Case for FAIL\nLive hook invocation against a running Claude Code session was not tested — could not\nconfirm the gate fires during an actual SubagentStop event.\n## Coverage Gaps\n- Checked: VAL-BEHAV-007 through VAL-BEHAV-011, all 6 test cases ran\n- Couldn'"'"'t check: live agent spawn during SubagentStop event\n## Feedback\nNo issues.\n' \
  > "$REPORT_F"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "both substantive → exit 0" 0
assert_eq "both substantive → empty stderr" "" "$HOOK_STDERR"

rm -f "$REPORT_F"

# ---------------------------------------------------------------------------
# Test 7: verdict independence — FAIL verdict with both sections → exit 0 (VAL-BEHAV-010)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: FAIL verdict with both sections passes ---'

REPORT_G="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Per-Criterion Results\n### Correctness Tier\n- [FAIL] criterion one — implementation missing\n## Overall Verdict: FAIL\n## Case for PASS\nIf the implementation existed and all criteria were met, the hook exit-code\nbehavior and section detection would have confirmed correctness.\n## Case for FAIL\nFile does not exist at the declared path; exit code assertions return non-zero;\nno tests pass against the absent implementation.\n## Coverage Gaps\n- Checked: file existence\n- Couldn'"'"'t check: runtime behavior\n## Feedback\nImplementation is missing.\n' \
  > "$REPORT_G"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "FAIL verdict with both sections → exit 0" 0

rm -f "$REPORT_G"

# ---------------------------------------------------------------------------
# Test 8: NEEDS_ITERATION verdict with both sections → exit 0 (VAL-BEHAV-010)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: NEEDS_ITERATION verdict with both sections passes ---'

REPORT_H="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: NEEDS_ITERATION\n## Case for PASS\nCore fast-path logic works; non-verifier agents exit 0 correctly.\n## Case for FAIL\nSection detection does not handle edge case where heading has trailing whitespace.\n## Coverage Gaps\n- Checked: basic path\n- Couldn'"'"'t check: edge case variants\n## Feedback\nEdge case not handled.\n' \
  > "$REPORT_H"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "NEEDS_ITERATION verdict with both sections → exit 0" 0

rm -f "$REPORT_H"

# ---------------------------------------------------------------------------
# Test 9: PASS_QUALITY_NEEDS_ITERATION verdict with both sections → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: PASS_QUALITY_NEEDS_ITERATION verdict with both sections passes ---'

REPORT_I="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS_QUALITY_NEEDS_ITERATION\n## Case for PASS\nAll Correctness criteria met with clear evidence.\n## Case for FAIL\nQuality tier has a missing naming convention check that could be tightened.\n## Coverage Gaps\n- Checked: all VAL assertions and Builder tests\n- Couldn'"'"'t check: long-running integration scenarios\n## Feedback\nQuality polish needed on naming.\n' \
  > "$REPORT_I"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "PASS_QUALITY_NEEDS_ITERATION verdict with both sections → exit 0" 0

rm -f "$REPORT_I"

# ---------------------------------------------------------------------------
# Test 10: false-positive guard — "none of the upstream" in Case for PASS → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: false-positive guard (none of the ...) passes ---'

REPORT_J="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS\n## Case for PASS\n- Checked: none of the upstream APIs were called — all logic is local and testable offline.\n## Case for FAIL\n- Live invocation could still miss timing-dependent behaviors.\n## Coverage Gaps\n- Checked: VAL-001 grep assertion\n- Couldn'"'"'t check: live API calls\n## Feedback\n' \
  > "$REPORT_J"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "none of the ... → exit 0 (no false positive)" 0

rm -f "$REPORT_J"

# ---------------------------------------------------------------------------
# Test 11: no active session → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: no active session → no-op ---'

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
# Test 12: VERIFIER CASE GATE appears in stderr on block (VAL-BEHAV-008)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- verifier-case-gate: VERIFIER CASE GATE phrase in block message ---'

REPORT_K="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS\n## Case for FAIL\nSome marginal cases remain.\n## Coverage Gaps\n- Checked: all\n- Couldn'"'"'t check: live spawn\n## Feedback\n' \
  > "$REPORT_K"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "missing Case for PASS → exit 2" 2
assert_contains "stderr contains VERIFIER CASE GATE phrase" "VERIFIER CASE GATE" "$HOOK_STDERR"

rm -f "$REPORT_K"

# ---------------------------------------------------------------------------
report
