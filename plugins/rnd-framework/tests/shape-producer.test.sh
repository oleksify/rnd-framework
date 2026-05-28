#!/usr/bin/env bash
# Tests for hooks/shape-producer.sh
# Usage: bash tests/shape-producer.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/shape-producer.sh"
PLUGIN_ROOT="${SCRIPT_DIR}/.."

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
SLUG="test-project-abc123"
SESSION_ID="20260501-120000-beef"
SESSION="${TMP_DIR}/.rnd/${SLUG}/branches/main/sessions/${SESSION_ID}"
mkdir -p "$SESSION"

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
        PLUGIN_ROOT="$PLUGIN_ROOT" \
        "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# Fixture validation-contract.md with 3 assertions spanning 2 tasks.
# features.json fixture maps assertions to tasks.
CONTRACT="${SESSION}/validation-contract.md"
FEATURES="${SESSION}/features.json"

printf '%s' \
'# Validation Contract

## Area: Helpers

### M1.helper.extracts-session-id
A helper extracts the session id.
Shape: wiring
Confidence: high

### M1.helper.assertion-parser-lifted
Parser lifted to shared location.
Shape: pure-refactor
Confidence: high

## Area: Producers

### M1.prod.emits-shape-facts
Producer emits shape facts.
Shape: wiring
Confidence: medium
' > "$CONTRACT"

printf '%s' \
'{
  "tasks": [
    {
      "id": "M1.T01.shared-helpers",
      "assertionIds": [
        "M1.helper.extracts-session-id",
        "M1.helper.assertion-parser-lifted"
      ]
    },
    {
      "id": "M1.T02.producers",
      "assertionIds": [
        "M1.prod.emits-shape-facts"
      ]
    }
  ]
}' > "$FEATURES"

# ---------------------------------------------------------------------------
# Test 1: 3-assertion fixture → exactly 3 assertion_shape lines
# ---------------------------------------------------------------------------
printf '%s\n' '--- shape-producer: 3-assertion contract → exactly 3 lines ---'

rm -f "${SESSION}/audit.jsonl"

run_producer "$CONTRACT"

assert_exit_code "3-assertion contract → exit 0" 0

LINE_COUNT="$(grep -c '"event":"assertion_shape"' "${SESSION}/audit.jsonl" 2>/dev/null || echo 0)"
assert_eq "exactly 3 assertion_shape lines" "3" "$LINE_COUNT"

# ---------------------------------------------------------------------------
# Test 2: assertion_ids match headings verbatim
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: assertion_ids match headings verbatim ---'

AUDIT_CONTENT="$(cat "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "assertion_id M1.helper.extracts-session-id present" \
  '"assertion_id":"M1.helper.extracts-session-id"' "$AUDIT_CONTENT"
assert_contains "assertion_id M1.helper.assertion-parser-lifted present" \
  '"assertion_id":"M1.helper.assertion-parser-lifted"' "$AUDIT_CONTENT"
assert_contains "assertion_id M1.prod.emits-shape-facts present" \
  '"assertion_id":"M1.prod.emits-shape-facts"' "$AUDIT_CONTENT"

# ---------------------------------------------------------------------------
# Test 3: shapes are valid x-shape-vocab values
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: shapes are valid x-shape-vocab values ---'

VALID_SHAPES="crud schema-migration external-integration pure-refactor perf auth data-transform wiring cleanup docs test-only behaviour misc"

while IFS= read -r line; do
  if printf '%s' "$line" | grep -q '"event":"assertion_shape"'; then
    SHAPE="$(printf '%s' "$line" | grep -o '"shape":"[^"]*"' | sed 's/"shape":"//;s/"//')"
    VALID=0
    for s in $VALID_SHAPES; do
      if [[ "$SHAPE" == "$s" ]]; then
        VALID=1
        break
      fi
    done
    assert_eq "shape '${SHAPE}' is valid x-shape-vocab" "1" "$VALID"
  fi
done < "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 4: task_id field is snake_case task id from features.json mapping
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: task_id is the owning task id ---'

LINE_T01="$(grep '"assertion_id":"M1.helper.extracts-session-id"' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "T01 assertion task_id is M1.T01.shared-helpers" \
  '"task_id":"M1.T01.shared-helpers"' "$LINE_T01"

LINE_T02="$(grep '"assertion_id":"M1.prod.emits-shape-facts"' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "T02 assertion task_id is M1.T02.producers" \
  '"task_id":"M1.T02.producers"' "$LINE_T02"

rm -f "${SESSION}/audit.jsonl"

# ---------------------------------------------------------------------------
# Test 5: relative file_path resolves to the correct session (FM1 guard)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: relative file_path → ≥1 emitted line ---'

# A relative path containing /sessions/ — the hook must not skip the emit.
# Run from TMP_DIR so the relative path resolves correctly.
RELATIVE_PATH="${SLUG}/branches/main/sessions/${SESSION_ID}/validation-contract.md"

# Write the contract at the relative path resolution (from TMP_DIR).
mkdir -p "${TMP_DIR}/${SLUG}/branches/main/sessions/${SESSION_ID}"
cp "$CONTRACT" "${TMP_DIR}/${SLUG}/branches/main/sessions/${SESSION_ID}/validation-contract.md"
cp "$FEATURES" "${TMP_DIR}/${SLUG}/branches/main/sessions/${SESSION_ID}/features.json"
AUDIT_IN_SESSION="${TMP_DIR}/${SLUG}/branches/main/sessions/${SESSION_ID}/audit.jsonl"
rm -f "$AUDIT_IN_SESSION"

HOOK_EXIT=0
HOOK_STDOUT=""
HOOK_STDERR=""
stdout_file="$(mktemp)"
stderr_file="$(mktemp)"

# Run from TMP_DIR so the relative path resolves against the fixture root.
printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${RELATIVE_PATH}\"}}" \
  | env -i PATH="$PATH" HOME="$HOME" \
      PLUGIN_ROOT="$PLUGIN_ROOT" \
      bash -c "cd '${TMP_DIR}' && '${HOOK}'" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

HOOK_STDOUT="$(cat "$stdout_file")"
HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "relative path → exit 0" 0

REL_LINE_COUNT="$(grep -c '"event":"assertion_shape"' "$AUDIT_IN_SESSION" 2>/dev/null || echo 0)"
assert_contains "relative path → ≥1 line emitted" "1" "$([ "$REL_LINE_COUNT" -ge 1 ] && echo '1 ok' || echo '0 fail')"

# ---------------------------------------------------------------------------
# Test 6: non-artifact path (no /sessions/) → exit 0, no emit
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: non-artifact path → exit 0, no emit ---'

rm -f "${SESSION}/audit.jsonl"

run_producer "/tmp/some-other-validation-contract.md"

assert_exit_code "non-artifact path → exit 0" 0
EMITTED="$(grep '"event":"assertion_shape"' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_eq "non-artifact path → no emit" "" "$EMITTED"

# ---------------------------------------------------------------------------
# Test 7: non-validation-contract path → exit 0, no emit
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: wrong filename → exit 0, no emit ---'

rm -f "${SESSION}/audit.jsonl"

run_producer "${SESSION}/protocol.md"

assert_exit_code "wrong filename → exit 0" 0
EMITTED="$(grep '"event":"assertion_shape"' "${SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_eq "wrong filename → no emit" "" "$EMITTED"

# ---------------------------------------------------------------------------
# Test 8: canonical write order — contract present, features.json ABSENT →
#         fire on the contract write → ZERO lines (no wrong-task fallback).
#         Guards the FM2/FM5 write-order hole.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: contract written before features.json → 0 lines ---'

WO_SESSION_ID="20260502-130000-cafe"
WO_SESSION="${TMP_DIR}/.rnd/${SLUG}/branches/main/sessions/${WO_SESSION_ID}"
mkdir -p "$WO_SESSION"
WO_CONTRACT="${WO_SESSION}/validation-contract.md"
WO_FEATURES="${WO_SESSION}/features.json"
WO_AUDIT="${WO_SESSION}/audit.jsonl"

cp "$CONTRACT" "$WO_CONTRACT"   # contract present, features.json NOT yet
rm -f "$WO_AUDIT"

run_producer "$WO_CONTRACT"

assert_exit_code "contract-only → exit 0" 0

WO_COUNT="$(grep -c '"event":"assertion_shape"' "$WO_AUDIT" 2>/dev/null || true)"
[[ -n "$WO_COUNT" ]] || WO_COUNT=0
assert_eq "contract present, features absent → 0 lines (no fallback)" "0" "$WO_COUNT"

# ---------------------------------------------------------------------------
# Test 9: features.json written second → fire on the features.json write →
#         exactly 3 lines, each task_id = owning task id (never the assertion id).
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: features.json written second → 3 lines, owning task_id ---'

cp "$FEATURES" "$WO_FEATURES"   # now BOTH present
rm -f "$WO_AUDIT"

run_producer "$WO_FEATURES"     # trigger on the features.json write

assert_exit_code "features.json trigger → exit 0" 0

WO_COUNT2="$(grep -c '"event":"assertion_shape"' "$WO_AUDIT" 2>/dev/null || true)"
[[ -n "$WO_COUNT2" ]] || WO_COUNT2=0
assert_eq "both present, fired on features.json → exactly 3 lines" "3" "$WO_COUNT2"

WO_LINE="$(grep '"assertion_id":"M1.helper.extracts-session-id"' "$WO_AUDIT" 2>/dev/null || true)"
assert_contains "task_id is owning task id (M1.T01.shared-helpers)" \
  '"task_id":"M1.T01.shared-helpers"' "$WO_LINE"
assert_eq "assertion_id never used as task_id" "" \
  "$(grep '"task_id":"M1.helper.extracts-session-id"' "$WO_AUDIT" 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Test 10: an assertion absent from all assertionIds[] is SKIPPED, not emitted
#          with task_id=assertion_id.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- shape-producer: unmapped assertion is skipped ---'

UM_SESSION_ID="20260503-140000-d00d"
UM_SESSION="${TMP_DIR}/.rnd/${SLUG}/branches/main/sessions/${UM_SESSION_ID}"
mkdir -p "$UM_SESSION"
UM_CONTRACT="${UM_SESSION}/validation-contract.md"
UM_FEATURES="${UM_SESSION}/features.json"
UM_AUDIT="${UM_SESSION}/audit.jsonl"

printf '%s' \
'# Validation Contract

### M1.helper.extracts-session-id
Mapped assertion.
Shape: wiring
Confidence: high

### M1.orphan.not-in-features
Unmapped assertion.
Shape: misc
Confidence: medium
' > "$UM_CONTRACT"

printf '%s' \
'{
  "tasks": [
    { "id": "M1.T01.shared-helpers", "assertionIds": ["M1.helper.extracts-session-id"] }
  ]
}' > "$UM_FEATURES"

rm -f "$UM_AUDIT"

run_producer "$UM_CONTRACT"

assert_exit_code "unmapped-assertion contract → exit 0" 0

UM_COUNT="$(grep -c '"event":"assertion_shape"' "$UM_AUDIT" 2>/dev/null || true)"
[[ -n "$UM_COUNT" ]] || UM_COUNT=0
assert_eq "only the mapped assertion is emitted (1 line)" "1" "$UM_COUNT"
assert_eq "orphan assertion not emitted" "" \
  "$(grep 'M1.orphan.not-in-features' "$UM_AUDIT" 2>/dev/null || true)"

# ---------------------------------------------------------------------------
report
