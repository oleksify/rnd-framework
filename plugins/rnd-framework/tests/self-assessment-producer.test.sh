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
# Test 1: full-template + DONE_WITH_CONCERNS → build_status=DONE_WITH_CONCERNS
#         (a pass-with-caveats is NOT a failure), path-derived ids
# ---------------------------------------------------------------------------
printf '%s\n' '--- self-assessment-producer: full-template + DONE_WITH_CONCERNS → that status, path-derived task_id ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T02.my-task-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'# Self-Assessment: M2.T02.my-task

**Status:** DONE_WITH_CONCERNS

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
assert_contains "build_status is DONE_WITH_CONCERNS (pass-with-caveats, not a fail)" '"build_status":"DONE_WITH_CONCERNS"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 2: minimal one-liner with Status: DONE → build_status=DONE
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: minimal one-liner + DONE → build_status DONE ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T03.another-task-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'# Self-Assessment: M2.T03.another-task

**Status:** DONE

All criteria met with HIGH confidence. No deviations. No unverified assumptions.
' > "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "minimal → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "build_status DONE for minimal" '"build_status":"DONE"' "$AUDIT_LINE"
assert_contains "task_id snake_case for minimal" '"task_id":"M2.T03.another-task"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 3: parallel-wave paths — each attributed to ITS OWN task, not most-recent
#         (path-not-ls-t guarantee)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: parallel-wave paths attributed by path ---'

SESSION2_ID="20260501-130000-cafe"
SESSION2="${TMP_DIR}/.rnd/${SLUG}/branches/main/sessions/${SESSION2_ID}"
mkdir -p "${SESSION2}/builds"

ASSESS1="${SESSION}/builds/M2.T02.task-a-self-assessment.md"
ASSESS2="${SESSION2}/builds/M2.T05.task-b-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "${SESSION2}/audit.jsonl" "$ASSESS1" "$ASSESS2"

printf '%s' '**Status:** DONE

All criteria met with HIGH confidence. No deviations. No unverified assumptions.' > "$ASSESS1"
printf '%s' \
'**Status:** BLOCKED

## Confidence per criterion
- criterion 1: LOW — cannot verify without live system' > "$ASSESS2"

# Fire for ASSESS1 — should write to SESSION1's audit.jsonl with task-a
run_producer "$ASSESS1"
assert_exit_code "session1 path → exit 0" 0
LINE1="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "session1 task attributed to task-a" '"task_id":"M2.T02.task-a"' "$LINE1"
assert_contains "session1 build_status DONE" '"build_status":"DONE"' "$LINE1"

# Fire for ASSESS2 — should write to SESSION2's audit.jsonl with task-b
run_producer "$ASSESS2"
assert_exit_code "session2 path → exit 0" 0
LINE2="$(grep 'builder_self_assessment' "${SESSION2}/audit.jsonl" 2>/dev/null || true)"
assert_contains "session2 task attributed to task-b" '"task_id":"M2.T05.task-b"' "$LINE2"
assert_contains "session2 build_status BLOCKED" '"build_status":"BLOCKED"' "$LINE2"

# Confirm no cross-contamination
CROSS="$(grep 'task-b' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_eq "no cross-contamination in session1 audit" "" "$CROSS"

rm -f "$ASSESS1" "$ASSESS2" "${SESSION}/audit.jsonl" "${SESSION2}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 4: non-artifact path → exit 0, no emit (non-artifact path guard)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: non-artifact path → exit 0, no emit ---'

rm -f "${SESSION}/audit.jsonl"

NON_ARTIFACT="/tmp/some-other-file-self-assessment.md"
run_producer "$NON_ARTIFACT"

assert_exit_code "non-artifact path → exit 0" 0
EMITTED="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_eq "non-artifact path → nothing emitted" "" "$EMITTED"

# ---------------------------------------------------------------------------
# Test 5: LOW confidence under DONE_WITH_CONCERNS → that status (NOT a fail).
#         A low-confidence criterion is no longer a failure on its own — the
#         status line is authoritative, the confidence token is not.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: LOW confidence + DONE_WITH_CONCERNS → that status (not a fail) ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T06.low-task-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'# Self-Assessment: M2.T06.low-task

**Status:** DONE_WITH_CONCERNS

## Confidence per criterion
- criterion 1: LOW — cannot verify without live deployment
' > "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "LOW confidence → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "LOW confidence under DONE_WITH_CONCERNS → that status" '"build_status":"DONE_WITH_CONCERNS"' "$AUDIT_LINE"

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
# Test 7: a file with NO Status line (legacy / forgotten) defaults to DONE.
#         Body words like "follows"/"below" must not flip it off the default.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: no Status line → defaults DONE ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T07.pass-oneliner-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'All criteria met; the implementation follows the pre-registered approach and stays well below the complexity ceiling. All tests green.' \
> "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "no-Status one-liner → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "no Status line → defaults DONE" '"build_status":"DONE"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 8: an inline MEDIUM/LOW confidence token WITHOUT a Status line no longer
#         implies failure — shape/keyword alone is not a status. Defaults DONE.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: inline MEDIUM token, no Status line → DONE (no shape inference) ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T08.inline-medium-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'Implemented and tested. Confidence: MEDIUM on the async edge case.' \
> "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "inline MEDIUM → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "inline MEDIUM token, no Status → DONE (formatting no longer implies failure)" '"build_status":"DONE"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 8a: explicit Status: BLOCKED → build_status=BLOCKED (a self-FAIL path).
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: explicit BLOCKED → build_status BLOCKED ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T09.blocked-task-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'# Self-Assessment: M2.T09.blocked-task

**Status:** BLOCKED

## Confidence per criterion
- criterion 1: LOW — external API unreachable, could not complete
' > "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "explicit BLOCKED → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "explicit BLOCKED → build_status BLOCKED" '"build_status":"BLOCKED"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 8b: explicit Status: NEEDS_CONTEXT → build_status=NEEDS_CONTEXT (a self-FAIL path).
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- self-assessment-producer: explicit NEEDS_CONTEXT → build_status NEEDS_CONTEXT ---'

ASSESSMENT_PATH="${SESSION}/builds/M2.T10.needs-context-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"

printf '%s' \
'# Self-Assessment: M2.T10.needs-context

**Status:** NEEDS_CONTEXT

## Uncertainties & risks
- Ambiguous requirement: cannot tell which schema version is authoritative
' > "$ASSESSMENT_PATH"

run_producer "$ASSESSMENT_PATH"

assert_exit_code "explicit NEEDS_CONTEXT → exit 0" 0

AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "explicit NEEDS_CONTEXT → build_status NEEDS_CONTEXT" '"build_status":"NEEDS_CONTEXT"' "$AUDIT_LINE"

rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 9–12: canonical task_id resolution against features.json.
# The stem is resolved to the canonical features.json id via the M<N>.T<NN>
# structural prefix, so a drifted/truncated slug still emits the joinable id.
# ---------------------------------------------------------------------------
FEATURES="${SESSION}/features.json"
printf '%s' '{
  "tasks": [
    {"id": "M1.T01.add-authentication-flow"},
    {"id": "M2.T01.unrelated-other-task"}
  ]
}' > "$FEATURES"

# Test 9: exact canonical filename → emits the id unchanged.
printf '\n%s\n' '--- self-assessment-producer: canonical filename → exact-match id ---'
ASSESSMENT_PATH="${SESSION}/builds/M1.T01.add-authentication-flow-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"
printf '%s' 'All criteria met with HIGH confidence.' > "$ASSESSMENT_PATH"
run_producer "$ASSESSMENT_PATH"
assert_exit_code "canonical filename → exit 0" 0
AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "exact id emitted" '"task_id":"M1.T01.add-authentication-flow"' "$AUDIT_LINE"
rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# Test 10: drifted/truncated slug → M<N>.T<NN> prefix resolves to the full id.
printf '\n%s\n' '--- self-assessment-producer: drifted slug → prefix self-heals to canonical id ---'
ASSESSMENT_PATH="${SESSION}/builds/M1.T01.add-au-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"
printf '%s' 'All criteria met with HIGH confidence.' > "$ASSESSMENT_PATH"
run_producer "$ASSESSMENT_PATH"
assert_exit_code "drifted slug → exit 0" 0
AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "drifted slug resolved to canonical id" '"task_id":"M1.T01.add-authentication-flow"' "$AUDIT_LINE"
rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# Test 11: milestone-less bare slot → unresolvable, falls back to raw stem.
printf '\n%s\n' '--- self-assessment-producer: bare T-slot (no milestone) → raw-stem fallback ---'
ASSESSMENT_PATH="${SESSION}/builds/T01-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"
printf '%s' 'All criteria met with HIGH confidence.' > "$ASSESSMENT_PATH"
run_producer "$ASSESSMENT_PATH"
assert_exit_code "bare slot → exit 0" 0
AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "bare slot falls back to raw stem" '"task_id":"T01"' "$AUDIT_LINE"
rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# Test 12: no features.json → raw stem fallback (never blocks).
printf '\n%s\n' '--- self-assessment-producer: no features.json → raw-stem fallback ---'
rm -f "$FEATURES"
ASSESSMENT_PATH="${SESSION}/builds/M1.T01.add-au-self-assessment.md"
rm -f "${SESSION}/audit.jsonl" "$ASSESSMENT_PATH"
printf '%s' 'All criteria met with HIGH confidence.' > "$ASSESSMENT_PATH"
run_producer "$ASSESSMENT_PATH"
assert_exit_code "no features.json → exit 0" 0
AUDIT_LINE="$(grep 'builder_self_assessment' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "no features.json → raw stem unchanged" '"task_id":"M1.T01.add-au"' "$AUDIT_LINE"
rm -f "$ASSESSMENT_PATH" "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
report
