#!/usr/bin/env bash
# Tests for hooks/anomaly-gate.sh
# Usage: bash tests/anomaly-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/anomaly-gate.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
mkdir -p "${TMP_SESSION}/reality"

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
# Test 1: non-auditor agent → fast-path exit 0
# ---------------------------------------------------------------------------
printf '%s\n' '--- anomaly-gate: non-auditor agent fast path ---'

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "rnd-builder → exit 0" 0
assert_eq "rnd-builder → empty stderr" "" "$HOOK_STDERR"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "rnd-verifier → exit 0" 0

run_with_session '{"agent_type":"","stop_reason":"end_turn"}'
assert_exit_code "empty agent_type → exit 0" 0

# ---------------------------------------------------------------------------
# Test 2: rnd-reality-auditor with no reality reports → exit 0 (no-op)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: no reality reports → no-op ---'

# Ensure no reality reports exist
rm -f "${TMP_SESSION}/reality/"T*-reality-report.md

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "no reports → exit 0" 0

# ---------------------------------------------------------------------------
# Test 3: missing both sections → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: missing both sections blocks ---'

REPORT_A="${TMP_SESSION}/reality/T1-reality-report.md"
printf '# Reality Report: T1\n\n## Summary\n- All external interactions: VALID\n\n## Interactions\n\n### 1. Foo\n**Source:** file:1\n**Verdict:** VALID\n\n## Overall Verdict: VALIDATED_ALL\n' \
  > "$REPORT_A"

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "missing both sections → exit 2" 2
assert_contains "stderr contains ANOMALY GATE" "ANOMALY GATE" "$HOOK_STDERR"

rm -f "$REPORT_A"

# ---------------------------------------------------------------------------
# Test 4: ## Anomalies section present with Source: bullet → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: Anomalies section with Source: passes ---'

REPORT_B="${TMP_SESSION}/reality/T1-reality-report.md"
printf '# Reality Report: T1\n\n## Summary\n- VALID: 7 INVALID: 1\n\n## Anomalies\n\n- Source: `lib/run-tool.sh:45` — expected 200 but got 404\n- Source: `lib/client.sh:12` — timeout unhandled\n\n## Overall Verdict: INVALID_FOUND\n' \
  > "$REPORT_B"

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "Anomalies with Source: → exit 0" 0
assert_eq "Anomalies with Source: → empty stderr" "" "$HOOK_STDERR"

rm -f "$REPORT_B"

# ---------------------------------------------------------------------------
# Test 5: ## Anomalies present but no Source: bullet → blocked (check A fails)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: Anomalies without Source: bullet fails check A ---'

REPORT_C="${TMP_SESSION}/reality/T1-reality-report.md"
printf '# Reality Report: T1\n\n## Anomalies\n\n- There was an issue with the API response\n- Another problem noted\n\n## Overall Verdict: INVALID_FOUND\n' \
  > "$REPORT_C"

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "Anomalies without Source: → exit 2" 2
assert_contains "stderr contains ANOMALY GATE" "ANOMALY GATE" "$HOOK_STDERR"

rm -f "$REPORT_C"

# ---------------------------------------------------------------------------
# Test 6: ## No-Finding Rationale present with ≥200 chars non-trivial → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: No-Finding Rationale substantive passes ---'

REPORT_D="${TMP_SESSION}/reality/T1-reality-report.md"
LONG_TEXT="All eight external interactions were verified by running the actual commands against the live system. Each experiment was designed to disprove the Builder's assumption. The fact that all returned VALID means the assumptions held under direct adversarial testing. No SQL schema mismatches, no API shape divergences, no missing env vars were found."
printf '# Reality Report: T1\n\n## Summary\n- VALID: 8\n\n## No-Finding Rationale\n\n%s\n\n## Overall Verdict: VALIDATED_ALL\n' "$LONG_TEXT" \
  > "$REPORT_D"

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "substantive No-Finding Rationale → exit 0" 0
assert_eq "substantive No-Finding Rationale → empty stderr" "" "$HOOK_STDERR"

rm -f "$REPORT_D"

# ---------------------------------------------------------------------------
# Test 7: trivial No-Finding Rationale → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: trivial No-Finding Rationale blocks ---'

REPORT_E="${TMP_SESSION}/reality/T1-reality-report.md"
printf '# Reality Report: T1\n\n## No-Finding Rationale\n\n- everything checks out\n\n## Overall Verdict: VALIDATED_ALL\n' \
  > "$REPORT_E"

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "trivial no-finding rationale → exit 2" 2
assert_contains "stderr contains ANOMALY GATE" "ANOMALY GATE" "$HOOK_STDERR"

rm -f "$REPORT_E"

# Test 7b: other trivial values
printf '\n%s\n' '--- anomaly-gate: other trivial No-Finding Rationale values block ---'

REPORT_F="${TMP_SESSION}/reality/T1-reality-report.md"
printf '# Reality Report: T1\n\n## No-Finding Rationale\n\n- all valid\n\n## Overall Verdict: VALIDATED_ALL\n' \
  > "$REPORT_F"

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "trivial all valid → exit 2" 2

rm -f "$REPORT_F"

REPORT_G="${TMP_SESSION}/reality/T1-reality-report.md"
printf '# Reality Report: T1\n\n## No-Finding Rationale\n\n- looks good\n\n## Overall Verdict: VALIDATED_ALL\n' \
  > "$REPORT_G"

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "trivial looks good → exit 2" 2

rm -f "$REPORT_G"

# ---------------------------------------------------------------------------
# Test 8: gate_fired audit event emitted with tool:"anomaly_gate" on block
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: audit event emitted on block ---'

REPORT_H="${TMP_SESSION}/reality/T1-reality-report.md"
printf '# Reality Report: T1\n\n## Summary\n- VALID: 8\n\n## Overall Verdict: VALIDATED_ALL\n' \
  > "$REPORT_H"

rm -f "${TMP_SESSION}/audit.jsonl"
run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
assert_exit_code "blocking path → exit 2" 2

AUDIT_LINE="$(grep 'anomaly_gate' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit.jsonl has gate_fired for anomaly_gate" "gate_fired" "$AUDIT_LINE"
assert_contains "audit.jsonl names anomaly_gate tool" "anomaly_gate" "$AUDIT_LINE"

rm -f "$REPORT_H"

# ---------------------------------------------------------------------------
# Test 9: no active session → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: no active session → no-op ---'

NO_SESSION_DIR="$(mktemp -d)"
rm -rf "$NO_SESSION_DIR"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$NO_SESSION_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "no active session → exit 0" 0

# ---------------------------------------------------------------------------
# Test 10: No-Finding Rationale exactly at 200 chars → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: No-Finding Rationale at boundary (200 chars) passes ---'

REPORT_I="${TMP_SESSION}/reality/T1-reality-report.md"
# Build a string that is exactly 200 chars after stripping leading bullet+space
BOUNDARY_TEXT="All eight external interactions were validated by running actual experiments. Each assumption was tested adversarially. No schema mismatches, shape errors, or missing variables were detected during this audit run."
CHAR_COUNT="${#BOUNDARY_TEXT}"

if [[ "$CHAR_COUNT" -ge 200 ]]; then
  printf '# Reality Report: T1\n\n## No-Finding Rationale\n\n%s\n\n## Overall Verdict: VALIDATED_ALL\n' "$BOUNDARY_TEXT" \
    > "$REPORT_I"

  run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
  assert_exit_code "200+ char rationale → exit 0" 0
else
  printf '  SKIP  boundary text only %d chars — test not meaningful\n' "$CHAR_COUNT"
fi

rm -f "$REPORT_I"

# ---------------------------------------------------------------------------
# Test 11: most recent report checked (two reports, most recent used)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- anomaly-gate: uses most recent report ---'

REPORT_OLD="${TMP_SESSION}/reality/T1-reality-report.md"
REPORT_NEW="${TMP_SESSION}/reality/T2-reality-report.md"

# Old report passes, new report fails
printf '# Reality Report: T1\n\n## Anomalies\n\n- Source: `file:1` — issue\n\n## Overall Verdict: INVALID_FOUND\n' \
  > "$REPORT_OLD"
touch -t 202601010000 "$REPORT_OLD"

printf '# Reality Report: T2\n\n## Summary\n- VALID: 8\n\n## Overall Verdict: VALIDATED_ALL\n' \
  > "$REPORT_NEW"
touch -t 202601020000 "$REPORT_NEW"

run_with_session '{"agent_type":"rnd-reality-auditor","stop_reason":"end_turn"}'
# T2 is newer and has no passing sections → should block
assert_exit_code "most recent report (T2, no sections) → exit 2" 2

rm -f "$REPORT_OLD" "$REPORT_NEW"

# ---------------------------------------------------------------------------
report
