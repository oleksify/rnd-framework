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
# Substance cases
# ---------------------------------------------------------------------------

# A runtime-unique tag. Because it is assembled at runtime from PID + $RANDOM,
# the contiguous string never appears as a literal in any git-tracked file or
# committed fixture, so "absent token" cases stay absent from the substance
# corpus regardless of whether this test file (or its fixtures) is committed.
# (The corpus is built from `git ls-files` over the repo plus the session dir.)
SUBST_TAG="M9SUBST${$}X${RANDOM}${RANDOM}"

# Build a single-entry verdict map inline (no committed fixture) so absent
# tokens never leak into the tracked corpus. The evidence item carries a `/`
# citation marker, so it passes the form pass and reaches the substance pass.
make_substance_map() {
  local assertion_id="$1"
  local evidence_item="$2"
  jq -nc \
    --arg id "$assertion_id" \
    --arg ev "$evidence_item" \
    '{($id): {verdict: "PASS", evidence: [$ev], feedback: "", task_id: "T01"}}'
}

# ---------------------------------------------------------------------------
# Case (i): substance-miss — citable token absent from corpus → exit 2
# The cited path token is built from SUBST_TAG, so it exists nowhere on disk.

MISS_TOKEN="${SUBST_TAG}/nonexistent.ts"
miss_map="$(make_substance_map "M9.substance.miss-test" "observed timeout referencing ${MISS_TOKEN} during the run")"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$miss_map")"
assert_exit "case (i): substance-miss → exit 2" 2
assert_stderr_contains "case (i): substance-miss → stderr contains SUBSTANCE FAILURE" "SUBSTANCE FAILURE"
assert_stderr_contains "case (i): substance-miss → stderr names offender ID" "M9.substance.miss-test"
assert_stderr_contains "case (i): substance-miss → stderr names missing token" "$MISS_TOKEN"

# ---------------------------------------------------------------------------
# Case (j): substance-hit-session — token present in a session artifact (outside excluded dirs)

mkdir -p "${FAKE_SESSION}/evidence/${SUBST_TAG}"
printf '{"result": "ok"}' > "${FAKE_SESSION}/evidence/${SUBST_TAG}/hit.json"

session_token="evidence/${SUBST_TAG}/hit.json"
session_map="$(make_substance_map "M9.substance.hit-session" "structured result written to ${session_token} confirmed")"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$session_map")"
assert_exit "case (j): substance-hit-session → exit 0" 0
assert_stderr_empty "case (j): substance-hit-session → no stderr"

# ---------------------------------------------------------------------------
# Case (k): substance-hit-source — token cites a real (git-tracked) repo file → exit 0

source_token="plugins/rnd-framework/lib/verdict-map-schema.json"
source_map="$(make_substance_map "M9.substance.hit-source" "schema sourced from ${source_token} confirmed present")"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$source_map")"
assert_exit "case (k): substance-hit-source → exit 0" 0
assert_stderr_empty "case (k): substance-hit-source → no stderr"

# FM4 canary: the unchanged valid-evidence.json and perf-200.json still pass with substance active.
run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture valid-evidence.json)")"
assert_exit "case (k): FM4 canary — valid-evidence.json still exits 0 with substance active" 0

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture perf-200.json)")"
assert_exit "case (k): FM4 canary — perf-200.json still exits 0 with substance active" 0

# ---------------------------------------------------------------------------
# Case (l): longest-span — extraction prefers the full /path run, not a fragment

# The evidence item embeds a path inside prose; extraction must pick the whole
# contiguous /-run (/src/<tag>/retry-handler.ts), never /src or /<tag>.
span_path="/src/${SUBST_TAG}/retry-handler.ts"
span_map="$(make_substance_map "M9.substance.longest-span" "timeout in ${span_path} module observed")"

# Sub-case (l-present): plant the file so the full path resolves in the session corpus → exit 0.
mkdir -p "${FAKE_SESSION}/src/${SUBST_TAG}"
printf 'retry handler stub' > "${FAKE_SESSION}/src/${SUBST_TAG}/retry-handler.ts"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$span_map")"
assert_exit "case (l-present): longest-span token present → exit 0" 0
assert_stderr_empty "case (l-present): longest-span token present → no stderr"

# Sub-case (l-absent): remove the file → exit 2, stderr names the FULL path, not a fragment.
rm -rf "${FAKE_SESSION}/src/${SUBST_TAG}"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$span_map")"
assert_exit "case (l-absent): longest-span token absent → exit 2" 2
assert_stderr_contains "case (l-absent): longest-span → SUBSTANCE FAILURE" "SUBSTANCE FAILURE"
assert_stderr_contains "case (l-absent): longest-span → stderr names full path not fragment" "$span_path"

# ---------------------------------------------------------------------------
# Case (m): prose-only — >=40-char item with no backtick/quote/slash → exempt → exit 0

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$(read_fixture prose-only-evidence.json)")"
assert_exit "case (m): prose-only evidence → exit 0" 0
assert_stderr_empty "case (m): prose-only evidence → no stderr"

# ---------------------------------------------------------------------------
# Case (n): verifications-self-ref — token planted ONLY in the excluded verifications/ dir
# Proves exclusion: the same setup under a non-excluded dir (case j) passes, but here it blocks.

verif_token="verifications/${SUBST_TAG}V/marker.json"
mkdir -p "${FAKE_SESSION}/verifications/${SUBST_TAG}V"
printf '{"marker": "ok"}' > "${FAKE_SESSION}/${verif_token}"
verif_map="$(make_substance_map "M9.substance.verif-self-ref" "verdict recorded at ${verif_token} in this wave")"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$verif_map")"
assert_exit "case (n): verifications-self-ref → exit 2 (excluded dir)" 2
assert_stderr_contains "case (n): verifications-self-ref → SUBSTANCE FAILURE" "SUBSTANCE FAILURE"

# ---------------------------------------------------------------------------
# Case (o): barrier-dir — token planted ONLY in the excluded builds/ dir; barrier content must not leak

barrier_token="builds/${SUBST_TAG}B/self-assessment.md"
barrier_content="${SUBST_TAG}B builder uncertainty prose that must never reach gate stderr"
mkdir -p "${FAKE_SESSION}/builds/${SUBST_TAG}B"
printf '%s' "$barrier_content" > "${FAKE_SESSION}/${barrier_token}"
barrier_map="$(make_substance_map "M9.substance.barrier-dir" "self-assessment stored at ${barrier_token} for this task")"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$barrier_map")"
assert_exit "case (o): barrier-dir → exit 2 (excluded dir)" 2
assert_stderr_contains "case (o): barrier-dir → SUBSTANCE FAILURE" "SUBSTANCE FAILURE"

# Barrier-protected content must not leak into stderr.
if [[ "$HOOK_STDERR" != *"builder uncertainty prose"* ]]; then
  pass "case (o): barrier-dir → barrier content absent from stderr"
else
  fail "case (o): barrier-dir → barrier content leaked into stderr"
fi

# ---------------------------------------------------------------------------
# Case (p): substance gate_fired audit event — exactly one, with offender ID

printf '' > "$FAKE_AUDIT"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$miss_map")"
assert_exit "case (p): substance-miss gate_fired → exit 2" 2

sub_event_count=0
if [[ -f "$FAKE_AUDIT" ]]; then
  sub_event_count="$(grep -c '"gate_fired"' "$FAKE_AUDIT" 2>/dev/null || true)"
fi

if [[ "$sub_event_count" -eq 1 ]]; then
  pass "case (p): substance block → exactly one gate_fired event"
else
  fail "case (p): substance block → expected 1 gate_fired event, found $sub_event_count"
fi

if grep -q '"evidence_locking_gate"' "$FAKE_AUDIT" 2>/dev/null; then
  pass "case (p): gate_fired event has tool: evidence_locking_gate"
else
  fail "case (p): gate_fired event missing 'evidence_locking_gate' in audit.jsonl"
fi

if grep -q '"M9.substance.miss-test"' "$FAKE_AUDIT" 2>/dev/null; then
  pass "case (p): gate_fired event carries substance offender assertion ID"
else
  fail "case (p): gate_fired event missing substance offender assertion ID in audit.jsonl"
fi

# ---------------------------------------------------------------------------
# Case (q): path:line citation — a real file cited as path:42 must resolve to
# the path core and PASS; an absent path cited as path:line must BLOCK naming
# the stripped path. (':' is a citation marker, so file:line is legitimate.)

pathline_present="$(make_substance_map "M9.substance.pathline-present" "guard confirmed at plugins/rnd-framework/lib/verdict-map-schema.json:5 during the run")"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$pathline_present")"
assert_exit "case (q-present): path:line citing a real file → exit 0" 0
assert_stderr_empty "case (q-present): path:line present → no stderr"

pathline_absent="$(make_substance_map "M9.substance.pathline-absent" "observed at ${SUBST_TAG}/missing-file.ts:42 during the run")"

run_hook "$(make_write_input "$VERDICT_MAP_PATH" "$pathline_absent")"
assert_exit "case (q-absent): path:line for an absent path → exit 2" 2
assert_stderr_contains "case (q-absent): path:line absent → SUBSTANCE FAILURE" "SUBSTANCE FAILURE"
assert_stderr_contains "case (q-absent): path:line absent → stderr names stripped path (no :42)" "${SUBST_TAG}/missing-file.ts"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
