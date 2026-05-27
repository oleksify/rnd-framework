#!/usr/bin/env bash
# Tests for hooks/builder-self-assessment-emit.sh
# Usage: bash tests/builder-self-assessment-emit.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/builder-self-assessment-emit.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
mkdir -p "${TMP_SESSION}/builds"

printf '20260401-120000-abcd' > "${TMP_BASE}/.current-session"
mkdir -p "${TMP_CONFIG}/.rnd"
printf '%s' "$TMP_BASE" > "${TMP_CONFIG}/.rnd/.active-base-dir"

cleanup() {
  rm -rf "$TMP_CONFIG"
}
trap cleanup EXIT

# Helper: run the hook with CLAUDE_CONFIG_DIR + RND_DIR pointed at the fixture.
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
# Test 1: full-template self-assessment → self_verdict=FAIL
#         (M1.emit.hook-emits-fail-on-concerns)
# ---------------------------------------------------------------------------
printf '%s\n' '--- builder-self-assessment-emit: full-template → FAIL ---'

rm -f "${TMP_SESSION}/audit.jsonl"
rm -f "${TMP_SESSION}/builds/"*-self-assessment.md

ASSESSMENT_A="${TMP_SESSION}/builds/M1.T01.my-task-self-assessment.md"
printf '%s' \
'# Self-Assessment: M1.T01.my-task

## Confidence per criterion
- criterion 1: MEDIUM — some uncertainty about edge cases

## Assumptions made

### Verified external assumptions
- (none)

### Unverified external assumptions
- (none)

## Uncertainties & risks
- Not sure about race condition in async path

## Deviations from plan
- (none)
' > "$ASSESSMENT_A"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'

assert_exit_code "full-template → exit 0 (non-blocking)" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit line has builder_self_assessment event" "builder_self_assessment" "$AUDIT_LINE"
assert_contains "audit line has self_verdict FAIL" '"self_verdict":"FAIL"' "$AUDIT_LINE"
assert_contains "audit line has correct task_id" '"task_id":"M1.T01.my-task"' "$AUDIT_LINE"
assert_contains "audit line has session_id" '"session_id":"20260401-120000-abcd"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_A" "${TMP_SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 2: minimal one-liner self-assessment → self_verdict=PASS
#         (M1.emit.hook-emits-pass-on-minimal)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-self-assessment-emit: minimal one-liner → PASS ---'

rm -f "${TMP_SESSION}/audit.jsonl"
rm -f "${TMP_SESSION}/builds/"*-self-assessment.md

ASSESSMENT_B="${TMP_SESSION}/builds/M1.T02.another-task-self-assessment.md"
printf '%s' \
'# Self-Assessment: M1.T02.another-task

All criteria met with HIGH confidence. No deviations. No unverified assumptions.
' > "$ASSESSMENT_B"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'

assert_exit_code "minimal one-liner → exit 0 (non-blocking)" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit line has builder_self_assessment event" "builder_self_assessment" "$AUDIT_LINE"
assert_contains "audit line has self_verdict PASS" '"self_verdict":"PASS"' "$AUDIT_LINE"
assert_contains "audit line has correct task_id" '"task_id":"M1.T02.another-task"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_B" "${TMP_SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 3a: non-builder agent → fast-path exit 0, nothing appended
#          (M1.emit.hook-non-blocking-and-fast-paths)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-self-assessment-emit: non-builder agent fast path ---'

rm -f "${TMP_SESSION}/audit.jsonl"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "rnd-verifier → exit 0" 0
assert_eq "rnd-verifier → empty stderr" "" "$HOOK_STDERR"

AUDIT_COUNT="$(grep -c 'builder_self_assessment' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || echo 0)"
assert_eq "rnd-verifier → no line appended" "0" "$AUDIT_COUNT"

run_with_session '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'
assert_exit_code "rnd-cleanup → exit 0" 0

run_with_session '{"agent_type":"","stop_reason":"end_turn"}'
assert_exit_code "empty agent_type → exit 0" 0

# ---------------------------------------------------------------------------
# Test 3b: no active session → fast-path exit 0, nothing appended
#          (M1.emit.hook-non-blocking-and-fast-paths)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-self-assessment-emit: no active session → no-op ---'

NO_SESSION_DIR="$(mktemp -d)"
rm -rf "$NO_SESSION_DIR"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-builder","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$NO_SESSION_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "no active session → exit 0" 0

# ---------------------------------------------------------------------------
# Test 3c: hook exits 0 even on internal error (no builds dir)
#          (M1.emit.hook-non-blocking-and-fast-paths)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-self-assessment-emit: no self-assessment file → still exit 0 ---'

rm -f "${TMP_SESSION}/builds/"*-self-assessment.md
rm -f "${TMP_SESSION}/audit.jsonl"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "no self-assessment file → exit 0 (non-blocking)" 0

# ---------------------------------------------------------------------------
# Test 4: full-template with LOW keyword → self_verdict=FAIL
#         Extra check to confirm the LOW keyword triggers FAIL
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-self-assessment-emit: LOW keyword in assessment → FAIL ---'

rm -f "${TMP_SESSION}/audit.jsonl"
rm -f "${TMP_SESSION}/builds/"*-self-assessment.md

ASSESSMENT_C="${TMP_SESSION}/builds/M1.T03.low-task-self-assessment.md"
printf '%s' \
'# Self-Assessment: M1.T03.low-task

## Confidence per criterion
- criterion 1: LOW — cannot verify without live deployment
' > "$ASSESSMENT_C"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'

assert_exit_code "LOW keyword → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "LOW keyword audit line has FAIL verdict" '"self_verdict":"FAIL"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_C" "${TMP_SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 5: event-shape matches gap-view consumer
#         (M1.emit.event-shape-matches-gap-view)
#         Structural check: the hook file contains both 'builder_self_assessment'
#         and 'self_verdict'; the SQL file also contains both.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-self-assessment-emit: event shape matches gap-view SQL ---'

HOOK_FILE="${SCRIPT_DIR}/../hooks/builder-self-assessment-emit.sh"
SQL_FILE="${SCRIPT_DIR}/../lib/stats/self_fail_vs_verdict_gap.sql"

HOOK_HAS_EVENT="$(grep -c 'builder_self_assessment' "$HOOK_FILE" 2>/dev/null || echo 0)"
assert_contains "hook file contains builder_self_assessment" "builder_self_assessment" "$(grep 'builder_self_assessment' "$HOOK_FILE" || true)"

HOOK_HAS_VERDICT="$(grep -c 'self_verdict' "$HOOK_FILE" 2>/dev/null || echo 0)"
assert_contains "hook file contains self_verdict" "self_verdict" "$(grep 'self_verdict' "$HOOK_FILE" || true)"

SQL_HAS_EVENT="$(grep -c 'builder_self_assessment' "$SQL_FILE" 2>/dev/null || echo 0)"
assert_contains "SQL file contains builder_self_assessment" "builder_self_assessment" "$(grep 'builder_self_assessment' "$SQL_FILE" || true)"

SQL_HAS_VERDICT="$(grep -c 'self_verdict' "$SQL_FILE" 2>/dev/null || echo 0)"
assert_contains "SQL file contains self_verdict" "self_verdict" "$(grep 'self_verdict' "$SQL_FILE" || true)"

# ---------------------------------------------------------------------------
# Test 6: picks the most-recently-modified self-assessment when multiple exist
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-self-assessment-emit: picks most-recent self-assessment ---'

rm -f "${TMP_SESSION}/audit.jsonl"
rm -f "${TMP_SESSION}/builds/"*-self-assessment.md

# Create an older full-template assessment first
ASSESSMENT_OLD="${TMP_SESSION}/builds/M1.T04.old-task-self-assessment.md"
printf '%s' \
'# Self-Assessment: M1.T04.old-task

## Confidence per criterion
- criterion 1: MEDIUM — some concern
' > "$ASSESSMENT_OLD"

# Small sleep to ensure mtime differs
sleep 1

# Create a newer minimal assessment
ASSESSMENT_NEW="${TMP_SESSION}/builds/M1.T05.new-task-self-assessment.md"
printf '%s' \
'# Self-Assessment: M1.T05.new-task

All criteria met with HIGH confidence. No deviations. No unverified assumptions.
' > "$ASSESSMENT_NEW"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'

assert_exit_code "most-recent pick → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "most-recent is new-task (PASS)" '"task_id":"M1.T05.new-task"' "$AUDIT_LINE"
assert_contains "most-recent self_verdict PASS" '"self_verdict":"PASS"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_OLD" "$ASSESSMENT_NEW" "${TMP_SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
report
