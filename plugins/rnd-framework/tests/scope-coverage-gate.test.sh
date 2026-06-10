#!/usr/bin/env bash
# Tests for hooks/scope-coverage-gate.sh
# Usage: bash tests/scope-coverage-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/scope-coverage-gate.sh"

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

SCOPE="${TMP_SESSION}/scope.json"
FEATURES="${TMP_SESSION}/features.json"

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

# A scope.json with two deliverables.
write_scope_two() {
  printf '%s' \
'{"deliverables":[{"id":"D1","title":"first"},{"id":"D2","title":"second"}],"task":"orig","frozen":true}' \
    > "$SCOPE"
}

# ---------------------------------------------------------------------------
# Test 1: fast-path — non-rnd-planner agent → exit 0, empty stderr
# Features carry a real creep violation to prove the fast path short-circuits.
# ---------------------------------------------------------------------------
printf '%s\n' '--- scope-coverage-gate: non-planner agent fast path ---'

write_scope_two
printf '%s' '{"tasks":[{"id":"M1.T01.a","deliverableIds":["D9"]}]}' > "$FEATURES"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "rnd-builder → exit 0" 0
assert_eq "rnd-builder → empty stderr" "" "$HOOK_STDERR"

run_with_session '{"agent_type":"","stop_reason":"end_turn"}'
assert_exit_code "empty agent_type → exit 0" 0
assert_eq "empty agent_type → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 2: fast-path — missing scope.json → exit 0, empty stderr
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-coverage-gate: missing scope.json → no-op ---'

rm -f "$SCOPE"
printf '%s' '{"tasks":[{"id":"M1.T01.a","deliverableIds":["D1"]}]}' > "$FEATURES"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "missing scope.json → exit 0" 0
assert_eq "missing scope.json → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 3: fast-path — legacy plan (no task has deliverableIds key) → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-coverage-gate: legacy plan fast path ---'

write_scope_two
printf '%s' '{"tasks":[{"id":"M1.T01.a"},{"id":"M1.T02.b"}]}' > "$FEATURES"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "legacy plan → exit 0" 0
assert_eq "legacy plan → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 4: scope_creep — task references an ID absent from scope.json → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-coverage-gate: unknown deliverable ID blocks (creep) ---'

rm -f "${TMP_SESSION}/audit.jsonl"
write_scope_two
printf '%s' '{"tasks":[{"id":"M1.T01.a","deliverableIds":["D1"]},{"id":"M1.T02.b","deliverableIds":["D2","D9"]}]}' > "$FEATURES"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "unknown D-ID → exit 2" 2
assert_contains "stderr names the gate" "scope-coverage-gate" "$HOOK_STDERR"
assert_contains "stderr names offending task" "M1.T02.b" "$HOOK_STDERR"

AUDIT_LINE="$(grep 'scope_coverage_gate' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit has scope_coverage_gate event" "scope_coverage_gate" "$AUDIT_LINE"
assert_contains "audit carries scope_creep kind" "scope_creep" "$AUDIT_LINE"

# ---------------------------------------------------------------------------
# Test 5: scope_creep — empty deliverableIds [] while field in use → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-coverage-gate: empty deliverableIds blocks (creep) ---'

rm -f "${TMP_SESSION}/audit.jsonl"
# D1 and D2 both covered by task a; task b has empty [] (orphan).
printf '%s' '{"tasks":[{"id":"M1.T01.a","deliverableIds":["D1","D2"]},{"id":"M1.T02.b","deliverableIds":[]}]}' > "$FEATURES"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "empty [] → exit 2" 2
assert_contains "stderr names orphan task" "M1.T02.b" "$HOOK_STDERR"

AUDIT_LINE="$(grep 'scope_coverage_gate' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit carries scope_creep kind" "scope_creep" "$AUDIT_LINE"

# ---------------------------------------------------------------------------
# Test 6: scope_miss — a deliverable covered by zero tasks → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-coverage-gate: uncovered deliverable blocks (miss) ---'

rm -f "${TMP_SESSION}/audit.jsonl"
write_scope_two
# D1 covered; D2 covered by nobody.
printf '%s' '{"tasks":[{"id":"M1.T01.a","deliverableIds":["D1"]}]}' > "$FEATURES"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "uncovered D-ID → exit 2" 2
assert_contains "stderr names the gate" "scope-coverage-gate" "$HOOK_STDERR"
assert_contains "stderr names uncovered deliverable" "D2" "$HOOK_STDERR"

AUDIT_LINE="$(grep 'scope_coverage_gate' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit carries scope_miss kind" "scope_miss" "$AUDIT_LINE"

# ---------------------------------------------------------------------------
# Test 7: fully-covered plan → exit 0, empty stderr
# Every task → >=1 valid D-ID, every D-ID → >=1 task.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-coverage-gate: fully-covered plan passes ---'

write_scope_two
printf '%s' '{"tasks":[{"id":"M1.T01.a","deliverableIds":["D1"]},{"id":"M1.T02.b","deliverableIds":["D2"]}]}' > "$FEATURES"

run_with_session '{"agent_type":"rnd-planner","stop_reason":"end_turn"}'
assert_exit_code "covered plan → exit 0" 0
assert_eq "covered plan → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 8: no active session → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-coverage-gate: no active session → no-op ---'

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
