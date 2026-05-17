#!/usr/bin/env bash
# Tests for hooks/coverage-gaps-gate.sh
# Usage: bash tests/coverage-gaps-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/coverage-gaps-gate.sh"

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
# Test 1: non-verifier agent → fast-path exit 0
# ---------------------------------------------------------------------------
printf '%s\n' '--- coverage-gaps-gate: non-verifier agent fast path ---'

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
printf '\n%s\n' '--- coverage-gaps-gate: no verification reports → no-op ---'

# Ensure no verification reports exist
rm -f "${TMP_SESSION}/verifications/"T*-verification.md

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "no reports → exit 0" 0

# ---------------------------------------------------------------------------
# Test 3: missing ## Coverage Gaps heading → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- coverage-gaps-gate: missing ## Coverage Gaps heading blocks ---'

REPORT_A="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Per-Criterion Results\n### Correctness Tier\n- [PASS] criterion one — evidence\n## Overall Verdict: PASS\n## Feedback\nNo issues.\n' \
  > "$REPORT_A"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "missing section → exit 2" 2
assert_contains "stderr contains coverage-gaps-gate" "coverage-gaps-gate" "$HOOK_STDERR"
assert_contains "stderr mentions Coverage Gaps" "Coverage Gaps" "$HOOK_STDERR"

rm -f "$REPORT_A"

# ---------------------------------------------------------------------------
# Test 4a: trivial content — bare "nothing" values → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- coverage-gaps-gate: trivial content (nothing/none) blocks ---'

REPORT_B="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Per-Criterion Results\n### Correctness Tier\n- [PASS] criterion one — evidence\n## Overall Verdict: PASS\n## Coverage Gaps\n- Checked: nothing\n- Couldn'"'"'t check: nothing\n## Feedback\nNo issues.\n' \
  > "$REPORT_B"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "trivial nothing → exit 2" 2
assert_contains "stderr contains coverage-gaps-gate" "coverage-gaps-gate" "$HOOK_STDERR"

rm -f "$REPORT_B"

# ---------------------------------------------------------------------------
# Test 4b: trivial content — bare "none" → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- coverage-gaps-gate: trivial content (bare none) blocks ---'

REPORT_C="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS\n## Coverage Gaps\n- Checked: none\n- Couldn'"'"'t check: none\n## Feedback\n' \
  > "$REPORT_C"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "trivial none → exit 2" 2

rm -f "$REPORT_C"

# ---------------------------------------------------------------------------
# Test 4c: trivial content — "all checks ran" → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- coverage-gaps-gate: trivial content (all checks ran) blocks ---'

REPORT_D="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS\n## Coverage Gaps\n- Checked: all checks ran\n- Couldn'"'"'t check: no gaps\n## Feedback\n' \
  > "$REPORT_D"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "trivial all checks ran → exit 2" 2

rm -f "$REPORT_D"

# ---------------------------------------------------------------------------
# Test 5: non-trivial content → exit 0 (passes through)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- coverage-gaps-gate: non-trivial content passes ---'

REPORT_E="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Per-Criterion Results\n### Correctness Tier\n- [PASS] criterion one — evidence\n## Overall Verdict: PASS\n## Coverage Gaps\n- Checked: VAL-COVGAPS-001 grep output matched, all 4 test cases ran, hook parse logic traced\n- Couldn'"'"'t check: live hook invocation against running Claude Code — requires a live agent spawn\n## Feedback\nNo issues.\n' \
  > "$REPORT_E"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "non-trivial content → exit 0" 0
assert_eq "non-trivial content → empty stderr" "" "$HOOK_STDERR"

rm -f "$REPORT_E"

# ---------------------------------------------------------------------------
# Test 6: false-positive guard — "none of the upstream APIs were reachable"
# The word "none" appears but is followed by other words — must NOT block.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- coverage-gaps-gate: false-positive guard (none of the ...) passes ---'

REPORT_F="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS\n## Coverage Gaps\n- Checked: VAL-001 grep assertion, bash parse check, exit code assertions\n- Couldn'"'"'t check: none of the upstream APIs were reachable during this verification run\n## Feedback\n' \
  > "$REPORT_F"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "none of the ... → exit 0 (no false positive)" 0

rm -f "$REPORT_F"

# ---------------------------------------------------------------------------
# Test 7: "Couldn't check: none — all VAL assertions passed" → should pass
# The pre-approved form from the skill guidance
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- coverage-gaps-gate: approved "none — all VAL assertions" form passes ---'

REPORT_G="${TMP_SESSION}/verifications/T1-verification.md"
printf '# Verification Report: T1\n## Overall Verdict: PASS\n## Coverage Gaps\n- Checked: VAL-001 grep exit 0, VAL-002 bash -n parse, all test assertions\n- Couldn'"'"'t check: none — all VAL assertions and experiment tests ran successfully against the implementation.\n## Feedback\n' \
  > "$REPORT_G"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "approved none-dash form → exit 0" 0

rm -f "$REPORT_G"

# ---------------------------------------------------------------------------
# Test 8: no active session → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- coverage-gaps-gate: no active session → no-op ---'

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
