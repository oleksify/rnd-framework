#!/usr/bin/env bash
# Tests for hooks/planner-emit-gate.sh
# Usage: bash tests/planner-emit-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/planner-emit-gate.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
mkdir -p "$TMP_SESSION"

printf '20260401-120000-abcd' > "${TMP_BASE}/.current-session"
mkdir -p "${TMP_CONFIG}/.rnd"
printf '%s' "$TMP_BASE" > "${TMP_CONFIG}/.rnd/.active-base-dir"

CONTRACT="${TMP_SESSION}/validation-contract.md"

cleanup() {
  rm -rf "$TMP_CONFIG"
}
trap cleanup EXIT

# Helper: run the hook with CLAUDE_CONFIG_DIR pointed at the fixture.
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
# Test 1: missing Shape: → exit 2 + names gate and offending assertion
# ---------------------------------------------------------------------------
printf '%s\n' '--- planner-emit-gate: assertion missing Shape: blocks ---'

rm -f "${TMP_SESSION}/audit.jsonl"
printf '%s' \
'## Area: Gate Behaviour

### M1.gate.no-shape
The gate fires when Shape is absent.
Claim: shape must be present.
Verified-by: bash tests/planner-emit-gate.test.sh exits 0
Confidence: high
' > "$CONTRACT"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "missing Shape → exit 2" 2
assert_contains "stderr names the gate" "planner-emit-gate" "$HOOK_STDERR"
assert_contains "stderr names offending assertion" "M1.gate.no-shape" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 2: Confidence: bogus → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- planner-emit-gate: bogus Confidence blocks ---'

printf '%s' \
'## Area: Gate Behaviour

### M1.gate.bad-confidence
The gate fires on an out-of-vocab confidence value.
Claim: confidence must be high|medium|stretch.
Verified-by: bash tests/planner-emit-gate.test.sh exits 0
Shape: wiring
Confidence: bogus
' > "$CONTRACT"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "bogus Confidence → exit 2" 2
assert_contains "stderr names offending assertion" "M1.gate.bad-confidence" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 3: fully-valid contract → exit 0, empty stderr
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- planner-emit-gate: fully-valid contract passes ---'

printf '%s' \
'## Area: Gate Behaviour

### M1.gate.valid-one
First valid assertion.
Claim: valid.
Verified-by: bash tests exits 0
Shape: wiring
Confidence: high

### M1.gate.valid-two
Second valid assertion with a different shape and confidence.
Claim: valid.
Verified-by: jq -e . hooks.json
Shape: schema-migration
Confidence: stretch

## Area: Other

### M1.other.valid-three
Third valid assertion in a second area.
Claim: valid.
Verified-by: grep matches
Shape: misc
Confidence: medium
' > "$CONTRACT"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "valid contract → exit 0" 0
assert_eq "valid contract → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 4: non-planner / empty agent_type → fast-path exit 0
# Contract still has an invalid assertion to prove the fast path short-circuits
# before any contract parsing.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- planner-emit-gate: non-planner agent fast path ---'

printf '%s' \
'## Area: Gate Behaviour

### M1.gate.no-shape
Would block for a planner, but the fast path must skip it.
Confidence: high
' > "$CONTRACT"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "rnd-builder → exit 0" 0
assert_eq "rnd-builder → empty stderr" "" "$HOOK_STDERR"

run_with_session '{"agent_type":"","stop_reason":"end_turn"}'
assert_exit_code "empty agent_type → exit 0" 0
assert_eq "empty agent_type → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 5: blocking path emits a gate_fired audit event for planner_emit_gate
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- planner-emit-gate: blocking path emits gate_fired audit event ---'

rm -f "${TMP_SESSION}/audit.jsonl"
printf '%s' \
'## Area: Gate Behaviour

### M1.gate.no-shape
Missing Shape triggers the gate and the audit event.
Claim: shape must be present.
Verified-by: bash tests exits 0
Confidence: high
' > "$CONTRACT"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "blocking path → exit 2" 2

AUDIT_LINE="$(grep 'planner_emit_gate' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit.jsonl has a planner_emit_gate event" "planner_emit_gate" "$AUDIT_LINE"
assert_contains "audit event is gate_fired" "gate_fired" "$AUDIT_LINE"

# ---------------------------------------------------------------------------
# Test 6: no validation-contract.md → exit 0 (no-op)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- planner-emit-gate: no contract → no-op ---'

rm -f "$CONTRACT"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "no contract → exit 0" 0
assert_eq "no contract → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 7: no active session → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- planner-emit-gate: no active session → no-op ---'

NO_SESSION_DIR="$(mktemp -d)"
rm -rf "$NO_SESSION_DIR"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-planner","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$NO_SESSION_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "no active session → exit 0" 0

# ---------------------------------------------------------------------------
report
