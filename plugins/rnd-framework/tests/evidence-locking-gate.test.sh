#!/usr/bin/env bash
# Tests for hooks/evidence-locking-gate.sh
# Usage: bash tests/evidence-locking-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/evidence-locking-gate.sh"
FIXTURE_DIR="${SCRIPT_DIR}/fixtures/evidence-locking"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_hook() {
  local stdin_json="$1"
  HOOK_STDOUT=""
  HOOK_STDERR=""
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$stdin_json" | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

pass() {
  local name="$1"
  printf 'PASS  %s\n' "$name"
  PASS=$((PASS + 1))
}

fail() {
  local name="$1"
  local detail="${2:-}"
  printf 'FAIL  %s%s\n' "$name" "${detail:+ — $detail}"
  FAIL=$((FAIL + 1))
}

assert_exit() {
  local name="$1"
  local expected="$2"
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expected, got $HOOK_EXIT"
  fi
}

assert_stderr_contains() {
  local name="$1"
  local needle="$2"
  if [[ "$HOOK_STDERR" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected stderr to contain '$needle', got: '$HOOK_STDERR'"
  fi
}

assert_stderr_empty() {
  local name="$1"
  if [[ -z "$HOOK_STDERR" ]]; then
    pass "$name"
  else
    fail "$name" "expected empty stderr, got: '$HOOK_STDERR'"
  fi
}

# ---------------------------------------------------------------------------
# Fake .rnd session for audit.jsonl testing
# ---------------------------------------------------------------------------
# is_plugin_artifact_path requires the path to match \.claude[^/]*/.*\.rnd/

RND_BASE="$(mktemp -d)"
FAKE_CONFIG="${RND_BASE}/.claude-test"
FAKE_RND="${FAKE_CONFIG}/.rnd"
FAKE_SLUG="${FAKE_RND}/test-project-abc123"
FAKE_BRANCH="${FAKE_SLUG}/branches/main"
FAKE_SESSION_ID="20260528-120000-abcd1234"
FAKE_SESSION="${FAKE_BRANCH}/sessions/${FAKE_SESSION_ID}"
FAKE_AUDIT="${FAKE_SESSION}/audit.jsonl"

mkdir -p "${FAKE_BRANCH}"
printf '%s' "${FAKE_BRANCH}" > "${FAKE_RND}/.active-base-dir"
printf '%s' "${FAKE_SESSION_ID}" > "${FAKE_BRANCH}/.current-session"
mkdir -p "${FAKE_SESSION}"
touch "$FAKE_AUDIT"

cleanup() {
  rm -rf "$RND_BASE"
}
trap cleanup EXIT

# Export CLAUDE_CONFIG_DIR so active_session_dir resolves to our fake session.
# This is required for the audit.jsonl test (case h).
export CLAUDE_CONFIG_DIR="$FAKE_CONFIG"

# Build a valid .rnd-anchored verdict-map path for hook path matching.
FAKE_VERIF_DIR="${FAKE_SESSION}/verifications"
mkdir -p "$FAKE_VERIF_DIR"
VERDICT_MAP_PATH="${FAKE_VERIF_DIR}/wave-1-verdict-map.json"

# Helper: build the hook stdin JSON for a Write call with fixture content.
make_write_input() {
  local path="$1"
  local content="$2"
  local agent="${3-rnd-verifier}"
  jq -nc \
    --arg tool "Write" \
    --arg path "$path" \
    --arg content "$content" \
    --arg agent "$agent" \
    '{tool_name: $tool, tool_input: {file_path: $path, content: $content}, agent_type: $agent}'
}

read_fixture() {
  local name="$1"
  cat "${FIXTURE_DIR}/${name}"
}

# ---------------------------------------------------------------------------
# Case (a): verifier write with evidence: [] → exit 2, stderr names offender
# ---------------------------------------------------------------------------

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture empty-evidence.json)")"
assert_exit "case (a): empty evidence → exit 2" 2
assert_stderr_contains "case (a): empty evidence → stderr names offender ID" "M6.hook.blocks-empty-evidence"
assert_stderr_contains "case (a): empty evidence → stderr names violation type" "empty"
assert_stderr_contains "case (a): empty evidence → stderr names schema path" "verdict-map-schema.json"

# ---------------------------------------------------------------------------
# Case (b): verifier write with evidence key missing → exit 2
# ---------------------------------------------------------------------------

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture missing-evidence.json)")"
assert_exit "case (b): missing evidence key → exit 2" 2
assert_stderr_contains "case (b): missing evidence → stderr names offender ID" "M6.hook.blocks-missing-evidence-field"
assert_stderr_contains "case (b): missing evidence → stderr contains 'missing'" "missing"

# ---------------------------------------------------------------------------
# Case (c): verifier write with evidence: ["passed"] → exit 2
# ---------------------------------------------------------------------------

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture trivial-single.json)")"
assert_exit "case (c): trivial single evidence → exit 2" 2
assert_stderr_contains "case (c): trivial single → stderr names offender ID" "M6.hook.blocks-trivial-evidence"
assert_stderr_contains "case (c): trivial single → stderr names violation type" "trivial"

# ---------------------------------------------------------------------------
# Case (d): every-not-any ["ran tests","compiles","no errors"] → exit 2
# ---------------------------------------------------------------------------

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture trivial-every-not-any.json)")"
assert_exit "case (d): every-not-any trivial evidence → exit 2" 2
assert_stderr_contains "case (d): every-not-any → stderr names offender ID" "M6.hook.blocks-trivial-evidence"
assert_stderr_contains "case (d): every-not-any → violation type is trivial" "trivial"

# ---------------------------------------------------------------------------
# Case (e): valid mixed-shape evidence → exit 0
# ---------------------------------------------------------------------------

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture valid-evidence.json)")"
assert_exit "case (e): valid mixed evidence → exit 0" 0
assert_stderr_empty "case (e): valid mixed evidence → no stderr"

# ---------------------------------------------------------------------------
# Case (f): non-verifier agent (empty / orchestrator) with bad evidence → exit 0
# ---------------------------------------------------------------------------

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture empty-evidence.json)" "")"
assert_exit "case (f): empty agent_type with bad evidence → exit 0 (pass-through)" 0
assert_stderr_empty "case (f): empty agent_type → no stderr"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture empty-evidence.json)" "rnd-integrator")"
assert_exit "case (f): integrator with bad evidence → exit 0 (pass-through)" 0
assert_stderr_empty "case (f): integrator → no stderr"

# ---------------------------------------------------------------------------
# Case (g): 200-assertion fixture → wall-clock <2s and exit 0
# ---------------------------------------------------------------------------

start_ts="$(python3 -c 'import time; print(int(time.time()*1000))')"
run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture perf-200.json)")"
end_ts="$(python3 -c 'import time; print(int(time.time()*1000))')"
elapsed=$((end_ts - start_ts))

assert_exit "case (g): 200-assertion fixture → exit 0" 0

if [[ "$elapsed" -lt 2000 ]]; then
  pass "case (g): 200-assertion fixture → wall-clock ${elapsed}ms < 2000ms"
else
  fail "case (g): 200-assertion fixture → wall-clock ${elapsed}ms exceeded 2000ms"
fi

# ---------------------------------------------------------------------------
# Case (h): gate_fired event appears in audit.jsonl exactly once per blocked write
# ---------------------------------------------------------------------------

# Reset audit log.
printf '' > "$FAKE_AUDIT"

# Write a fake .active-base-dir pointing at our fake branch so active_session_dir resolves.
# (Already set up above; just confirm the session dir exists.)

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture empty-evidence.json)")"
assert_exit "case (h): block triggers exit 2" 2

# Count gate_fired events in audit.jsonl.
event_count=0
if [[ -f "$FAKE_AUDIT" ]]; then
  event_count="$(grep -c '"gate_fired"' "$FAKE_AUDIT" 2>/dev/null || true)"
fi

if [[ "$event_count" -eq 1 ]]; then
  pass "case (h): exactly one gate_fired event written to audit.jsonl"
else
  fail "case (h): expected 1 gate_fired event, found $event_count"
fi

# Verify the gate name in the event.
gate_name_found=0
if grep -q '"evidence_locking_gate"' "$FAKE_AUDIT" 2>/dev/null; then
  gate_name_found=1
fi

if [[ "$gate_name_found" -eq 1 ]]; then
  pass "case (h): gate_fired event has tool: evidence_locking_gate"
else
  fail "case (h): gate_fired event missing 'evidence_locking_gate' in audit.jsonl"
fi

# Verify the offender assertion_id appears in task_id field.
offender_found=0
if grep -q '"M6.hook.blocks-empty-evidence"' "$FAKE_AUDIT" 2>/dev/null; then
  offender_found=1
fi

if [[ "$offender_found" -eq 1 ]]; then
  pass "case (h): gate_fired event carries first offender assertion ID as task_id"
else
  fail "case (h): gate_fired event missing offender assertion ID in audit.jsonl"
fi

# Second blocked write should produce exactly one more event (not two total extra).
printf '' > "$FAKE_AUDIT"
run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture trivial-single.json)")"
second_count=0
if [[ -f "$FAKE_AUDIT" ]]; then
  second_count="$(grep -c '"gate_fired"' "$FAKE_AUDIT" 2>/dev/null || true)"
fi

if [[ "$second_count" -eq 1 ]]; then
  pass "case (h): second blocked write emits exactly one gate_fired event"
else
  fail "case (h): second blocked write emitted $second_count gate_fired events (expected 1)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
