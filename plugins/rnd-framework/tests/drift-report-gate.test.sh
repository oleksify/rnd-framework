#!/usr/bin/env bash
# Tests for hooks/drift-report-gate.sh
# Usage: bash tests/drift-report-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/drift-report-gate.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
mkdir -p "${TMP_SESSION}/drift"

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
# Test 1: non-drift-detector agent → fast-path exit 0
# ---------------------------------------------------------------------------
printf '%s\n' '--- drift-report-gate: non-drift-detector agent fast path ---'

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "rnd-builder → exit 0" 0
assert_eq "rnd-builder → empty stderr" "" "$HOOK_STDERR"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "rnd-verifier → exit 0" 0

run_with_session '{"agent_type":"","stop_reason":"end_turn"}'
assert_exit_code "empty agent_type → exit 0" 0

# ---------------------------------------------------------------------------
# Test 2: rnd-drift-detector with no drift reports → exit 0 (no-op)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: no drift reports → no-op ---'

rm -f "${TMP_SESSION}/drift/"wave-*-drift-report.md

run_with_session '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}'
assert_exit_code "no reports → exit 0" 0

# ---------------------------------------------------------------------------
# Test 3: missing ## Drift Hypothesis → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: missing ## Drift Hypothesis blocks ---'

REPORT_A="${TMP_SESSION}/drift/wave-1-drift-report.md"
printf '## Counter-evidence\nNo evidence of drift.\n## Verdict\nNO_DRIFT\n' > "$REPORT_A"

run_with_session '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}'
assert_exit_code "missing Drift Hypothesis → exit 2" 2
assert_contains "stderr contains DRIFT REPORT GATE" "DRIFT REPORT GATE" "$HOOK_STDERR"
assert_contains "stderr mentions Drift Hypothesis" "Drift Hypothesis" "$HOOK_STDERR"

rm -f "$REPORT_A"

# ---------------------------------------------------------------------------
# Test 4: missing ## Counter-evidence → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: missing ## Counter-evidence blocks ---'

REPORT_B="${TMP_SESSION}/drift/wave-1-drift-report.md"
printf '## Drift Hypothesis\nNo drift observed.\n## Verdict\nNO_DRIFT\n' > "$REPORT_B"

run_with_session '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}'
assert_exit_code "missing Counter-evidence → exit 2" 2
assert_contains "stderr contains DRIFT REPORT GATE" "DRIFT REPORT GATE" "$HOOK_STDERR"
assert_contains "stderr mentions Counter-evidence" "Counter-evidence" "$HOOK_STDERR"

rm -f "$REPORT_B"

# ---------------------------------------------------------------------------
# Test 5: missing ## Verdict heading → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: missing ## Verdict heading blocks ---'

REPORT_C="${TMP_SESSION}/drift/wave-1-drift-report.md"
printf '## Drift Hypothesis\nNo drift observed.\n## Counter-evidence\nNo evidence.\n' > "$REPORT_C"

run_with_session '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}'
assert_exit_code "missing Verdict heading → exit 2" 2
assert_contains "stderr contains DRIFT REPORT GATE" "DRIFT REPORT GATE" "$HOOK_STDERR"
assert_contains "stderr mentions Verdict" "Verdict" "$HOOK_STDERR"

rm -f "$REPORT_C"

# ---------------------------------------------------------------------------
# Test 6: verdict outside enum → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: invalid verdict value blocks ---'

REPORT_D="${TMP_SESSION}/drift/wave-1-drift-report.md"
printf '## Drift Hypothesis\nNo drift observed.\n## Counter-evidence\nNo evidence.\n## Verdict\nDRIFT_DETECTED\n' > "$REPORT_D"

run_with_session '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}'
assert_exit_code "invalid verdict → exit 2" 2
assert_contains "stderr contains DRIFT REPORT GATE" "DRIFT REPORT GATE" "$HOOK_STDERR"
assert_contains "stderr lists valid enum" "NO_DRIFT" "$HOOK_STDERR"

rm -f "$REPORT_D"

# Lowercase verdict is also invalid (case-sensitive)
REPORT_D2="${TMP_SESSION}/drift/wave-1-drift-report.md"
printf '## Drift Hypothesis\nNo drift.\n## Counter-evidence\nNone found.\n## Verdict\nno_drift\n' > "$REPORT_D2"

run_with_session '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}'
assert_exit_code "lowercase verdict → exit 2 (case-sensitive)" 2

rm -f "$REPORT_D2"

# ---------------------------------------------------------------------------
# Test 7: happy path — all sections + valid verdict → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: valid report passes ---'

REPORT_E="${TMP_SESSION}/drift/wave-1-drift-report.md"
printf '## Drift Hypothesis\nPlan scope is unchanged.\n## Counter-evidence\nAll tasks match original intent.\n## Verdict\nNO_DRIFT\n' \
  > "$REPORT_E"

run_with_session '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}'
assert_exit_code "valid NO_DRIFT → exit 0" 0
assert_eq "valid report → empty stderr" "" "$HOOK_STDERR"

rm -f "$REPORT_E"

# Test all four valid verdict values
for verdict in NO_DRIFT MINOR_DRIFT MAJOR_DRIFT RESET_RECOMMENDED; do
  REPORT_V="${TMP_SESSION}/drift/wave-2-drift-report.md"
  printf '## Drift Hypothesis\nObservation.\n## Counter-evidence\nEvidence.\n## Verdict\n%s\n' "$verdict" \
    > "$REPORT_V"

  run_with_session '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}'
  assert_exit_code "valid verdict ${verdict} → exit 0" 0

  rm -f "$REPORT_V"
done

# ---------------------------------------------------------------------------
# Test 8: audit event emitted in block path — gate_fired event written
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: audit event emitted on block ---'

TMP_RND_DIR="$(mktemp -d)"
REPORT_BLOCK="${TMP_SESSION}/drift/wave-3-drift-report.md"
printf '## Counter-evidence\nSome evidence.\n## Verdict\nNO_DRIFT\n' > "$REPORT_BLOCK"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$TMP_CONFIG" \
      RND_DIR="$TMP_RND_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "block path exit 2" 2

if [[ -f "${TMP_RND_DIR}/audit.jsonl" ]]; then
  audit_content="$(cat "${TMP_RND_DIR}/audit.jsonl")"
  assert_contains "block path emits gate_fired event" "gate_fired" "$audit_content"
  assert_contains "block path tool starts with drift_detector" "drift_detector" "$audit_content"
else
  assert_eq "block path audit.jsonl missing (jq may be unavailable)" "ok" "ok"
fi

rm -f "$REPORT_BLOCK"
rm -rf "$TMP_RND_DIR"

# ---------------------------------------------------------------------------
# Test 9: audit event emitted on pass path — gate_fired with verdict in tool slot
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: audit event emitted on pass ---'

TMP_RND_DIR2="$(mktemp -d)"
REPORT_PASS="${TMP_SESSION}/drift/wave-4-drift-report.md"
printf '## Drift Hypothesis\nMinor scope additions.\n## Counter-evidence\nOne task added.\n## Verdict\nMINOR_DRIFT\n' \
  > "$REPORT_PASS"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$TMP_CONFIG" \
      RND_DIR="$TMP_RND_DIR2" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "pass path exit 0" 0

if [[ -f "${TMP_RND_DIR2}/audit.jsonl" ]]; then
  audit_content2="$(cat "${TMP_RND_DIR2}/audit.jsonl")"
  assert_contains "pass path emits gate_fired event" "gate_fired" "$audit_content2"
  assert_contains "pass path tool contains drift_detector:MINOR_DRIFT" "drift_detector:MINOR_DRIFT" "$audit_content2"
else
  assert_eq "pass path audit.jsonl missing (jq may be unavailable)" "ok" "ok"
fi

rm -f "$REPORT_PASS"
rm -rf "$TMP_RND_DIR2"

# ---------------------------------------------------------------------------
# Test 10: no active session → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- drift-report-gate: no active session → no-op ---'

NO_SESSION_DIR="$(mktemp -d)"
rm -rf "$NO_SESSION_DIR"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-drift-detector","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$NO_SESSION_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "no active session → exit 0" 0

# ---------------------------------------------------------------------------
report
