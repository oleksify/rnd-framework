#!/usr/bin/env bash
# Tests for hooks/self-assessment-producer.sh
# Usage: bash tests/self-assessment-producer.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/self-assessment-producer.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
SLUG="test-project-abc123"
SESSION_ID="20260501-120000-beef"
SESSION="${TMP_DIR}/.rnd/${SLUG}/branches/main/sessions/${SESSION_ID}"
mkdir -p "${SESSION}/builds"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Helper: run the hook with a tool_input.file_path pointing at the fixture.
run_producer() {
  local file_path="$1"
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${file_path}\"}}" \
    | env -i PATH="$PATH" HOME="$HOME" \
        "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# ---------------------------------------------------------------------------
# Test 1: full-template self-assessment → self_verdict=FAIL, path-derived ids
#         (M2.selfassess.emits-self-verdict-keyed-by-path)
# ---------------------------------------------------------------------------
printf '%s\n' '--- self-assessment-producer: full-template → FAIL, path-derived task_id ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T02.my-task-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'# Self-Assessment: M2.T02.my-task

## Confidence per criterion
- criterion 1: MEDIUM — some uncertainty about edge cases

## Assumptions made

### Unverified external assumptions
- (none)

## Uncertainties & risks
- Not sure about race condition in async path

## Deviations from plan
- (none)
' > "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "full-template → exit 0 (non-blocking)" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit line emitted" "builder_self_assessment" "$AUDIT_LINE"
assert_contains "task_id is snake_case" '"task_id":"M2.T02.my-task"' "$AUDIT_LINE"
assert_contains "session_id derived from path" "\"session_id\":\"${SESSION_ID}\"" "$AUDIT_LINE"
assert_contains "self_verdict is FAIL for full-template" '"self_verdict":"FAIL"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 2: minimal one-liner self-assessment → self_verdict=PASS
#         (M2.selfassess.emits-self-verdict-keyed-by-path)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: minimal one-liner → PASS ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T03.another-task-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'# Self-Assessment: M2.T03.another-task

All criteria met with HIGH confidence. No deviations. No unverified assumptions.
' > "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "minimal → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "self_verdict PASS for minimal" '"self_verdict":"PASS"' "$AUDIT_LINE"
assert_contains "task_id snake_case for minimal" '"task_id":"M2.T03.another-task"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 3: parallel-wave paths — each attributed to ITS OWN task, not most-recent
#         (M2.selfassess.emits-self-verdict-keyed-by-path — path-not-ls-t guarantee)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: parallel-wave paths attributed by path ---'

SESSION2_ID="20260501-130000-cafe"
SESSION2="${TMP_DIR}/.rnd/${SLUG}/branches/main/sessions/${SESSION2_ID}"
mkdir -p "${SESSION2}/builds"

ASSESS1="${SESSION}/builds/M2.T02.task-a-self-assessment.md"
ASSESS2="${SESSION2}/builds/M2.T05.task-b-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "${SESSION2}/audit.jsonl" "$ASSESS1" "$ASSESS2"

printf '%s' 'All criteria met with HIGH confidence. No deviations. No unverified assumptions.' > "$ASSESS1"
printf '%s' \
'## Confidence per criterion
- criterion 1: LOW — cannot verify without live system' > "$ASSESS2"

# Fire for ASSESS1 — should write to SESSION1's audit.jsonl with task-a
run_producer "$ASSESS1"
assert_exit_code "session1 path → exit 0" 0
LINE1="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "session1 task attributed to task-a" '"task_id":"M2.T02.task-a"' "$LINE1"
assert_contains "session1 self_verdict PASS" '"self_verdict":"PASS"' "$LINE1"

# Fire for ASSESS2 — should write to SESSION2's audit.jsonl with task-b
run_producer "$ASSESS2"
assert_exit_code "session2 path → exit 0" 0
LINE2="$(grep 'builder_self_assessment' "${SESSION2}/audit.jsonl" 2>/dev/null || true)"
assert_contains "session2 task attributed to task-b" '"task_id":"M2.T05.task-b"' "$LINE2"
assert_contains "session2 self_verdict FAIL" '"self_verdict":"FAIL"' "$LINE2"

# Confirm no cross-contamination
CROSS="$(grep 'task-b' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_eq "no cross-contamination in session1 audit" "" "$CROSS"

rm -f "$ASSESS1" "$ASSESS2" "${SESSION}/audit.jsonl" "${SESSION2}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 4: non-artifact path → exit 0, no emit
#         (M2.shape.relative-file-path-does-not-skip — non-artifact path guard)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: non-artifact path → exit 0, no emit ---'

rm -f "${SESSION}/audit.jsonl"

NON_ARTIFACT="/tmp/some-other-file-self-assessment.md"
run_producer "$NON_ARTIFACT"

assert_exit_code "non-artifact path → exit 0" 0
EMITTED="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_eq "non-artifact path → nothing emitted" "" "$EMITTED"

# ---------------------------------------------------------------------------
# Test 5: LOW keyword in self-assessment → self_verdict=FAIL
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: LOW keyword → FAIL ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T06.low-task-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'# Self-Assessment: M2.T06.low-task

## Confidence per criterion
- criterion 1: LOW — cannot verify without live deployment
' > "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "LOW keyword → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "LOW keyword → FAIL verdict" '"self_verdict":"FAIL"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 6: path with no /sessions/ segment → exit 0, no emit
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: path with no /sessions/ → exit 0, no emit ---'

rm -f "${SESSION}/audit.jsonl"

run_producer "/home/user/documents/some-self-assessment.md"

assert_exit_code "no /sessions/ path → exit 0" 0
EMITTED="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_eq "no /sessions/ → nothing emitted" "" "$EMITTED"

# ---------------------------------------------------------------------------
# Test 7: minimal PASS one-liner containing ordinary words with the "low"
#         substring ("follows", "below") must NOT be misclassified FAIL.
#         Regression for the non-portable `grep -qi "MEDIUM\|LOW"` substring bug.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: PASS one-liner with "follows"/"below" stays PASS ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T07.pass-oneliner-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'All criteria met; the implementation follows the pre-registered approach and stays well below the complexity ceiling. All tests green.' \
> "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "PASS one-liner → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "one-liner with follows/below → PASS verdict (no substring false-match)" '"self_verdict":"PASS"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 8: inline MEDIUM/LOW confidence token WITHOUT section headings still
#         classifies FAIL (the word-anchored grep branch fires on the real token).
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: inline MEDIUM confidence (no headings) → FAIL ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T08.inline-medium-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'Implemented and tested. Confidence: MEDIUM on the async edge case.' \
> "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "inline MEDIUM → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "inline MEDIUM token → FAIL verdict" '"self_verdict":"FAIL"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
report
