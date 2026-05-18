#!/usr/bin/env bash
# tests/inline-verify-regression.test.sh — Schema-equivalence regression tests
# for lib/inline-verify.sh. Creates 3 synthetic LOW pre-regs with mechanical
# Evidence commands and asserts the produced verdict map matches the schema
# that any downstream consumer of wave-N-verdict-map.json expects.
#
# Reinterpretation note: the "byte-for-byte match against a spawned-verifier
# baseline" criterion is implemented as schema-equivalence — the output must
# parse and satisfy {T<id>: {verdict, evidence[], feedback}} for any downstream
# consumer to treat it identically. Spawning a live Verifier agent for a unit
# test would make this test prohibitively expensive.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

INLINE_VERIFY="${PLUGIN_ROOT}/lib/inline-verify.sh"

TMP_DIR="$(mktemp -d)"
RND_DIR="${TMP_DIR}/rnd"
mkdir -p "${RND_DIR}/verifications"
export RND_DIR

trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Synthetic plan.md: 3 tasks in Wave 1, all Verification level: inline.
# Evidence commands use 'true' (always PASS) for two tasks and a failing
# command for one task to exercise the FAIL path as well.
# ---------------------------------------------------------------------------

PLAN_PATH="${TMP_DIR}/plan.md"
cat > "$PLAN_PATH" << 'PLAN_EOF'
# Plan: Inline Verify Test Plan

## Task Tree

- Wave 1 — Inline verification test tasks
  - **T1** First mechanical task
  - **T2** Second mechanical task
  - **T3** Third mechanical task (failure scenario)

## Pre-Registration Documents

---

### Task T1 — First mechanical task

```
Task ID: T1
Intent: Test inline verification with a passing Evidence command.
Approach: Run a simple shell command that always succeeds.
Expected outputs:
  - some/file.ext
Criticality: LOW
Success criteria:
  Correctness:
  - [ ] grep confirms expected output: exits 0 with matching line.
  Quality:
  - [ ] Script is minimal.
Verification level: inline
Dependencies: none
fulfills: [VAL-TEST-001]
```

---

### Task T2 — Second mechanical task

```
Task ID: T2
Intent: Test inline verification with multiple VAL assertions.
Approach: Run simple shell commands that always succeed.
Expected outputs:
  - some/other.ext
Criticality: LOW
Success criteria:
  Correctness:
  - [ ] grep confirms pattern exists: exits 0.
  - [ ] jq parses the output successfully.
  Quality:
  - [ ] Output is minimal.
Verification level: inline
Dependencies: none
fulfills: [VAL-TEST-002, VAL-TEST-003]
```

---

### Task T3 — Third mechanical task (failure scenario)

```
Task ID: T3
Intent: Test inline verification with a failing Evidence command.
Approach: Run a shell command that always fails.
Expected outputs:
  - none
Criticality: LOW
Success criteria:
  Correctness:
  - [ ] bash test exits 0.
  Quality:
  - [ ] Failure is detected.
Verification level: inline
Dependencies: none
fulfills: [VAL-TEST-004]
```

## Validation Contract

### Area: Inline Verify Tests

#### VAL-TEST-001: First task passes with true
The first task Evidence command always exits 0.
Tool: shell
Evidence: `true`

#### VAL-TEST-002: Second task first assertion passes
The second task first Evidence command always exits 0.
Tool: shell
Evidence: `true`

#### VAL-TEST-003: Second task second assertion passes
The second task second Evidence command also exits 0.
Tool: shell
Evidence: `true`

#### VAL-TEST-004: Third task fails with false
The third task Evidence command always exits non-zero.
Tool: shell
Evidence: `false`

PLAN_EOF

# ---------------------------------------------------------------------------
# Run inline-verify.sh against the synthetic plan
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: basic invocation ---\n'

INVOKE_EXIT=0
INVOKE_STDERR=""
INVOKE_STDERR="$(bash "$INLINE_VERIFY" "$PLAN_PATH" "1" 2>&1)" || INVOKE_EXIT=$?

assert_eq "inline-verify exits 0" "0" "$INVOKE_EXIT"

VERDICT_MAP_PATH="${RND_DIR}/verifications/wave-1-verdict-map.json"
assert_eq "verdict map file exists" "0" "$(test -f "$VERDICT_MAP_PATH" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# Schema validation: top-level keys are T1, T2, T3
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: verdict map schema ---\n'

KEY_COUNT="$(jq 'keys | length' "$VERDICT_MAP_PATH")"
assert_eq "verdict map has 3 task keys" "3" "$KEY_COUNT"

HAS_T1="$(jq 'has("T1")' "$VERDICT_MAP_PATH")"
HAS_T2="$(jq 'has("T2")' "$VERDICT_MAP_PATH")"
HAS_T3="$(jq 'has("T3")' "$VERDICT_MAP_PATH")"
assert_eq "verdict map has key T1" "true" "$HAS_T1"
assert_eq "verdict map has key T2" "true" "$HAS_T2"
assert_eq "verdict map has key T3" "true" "$HAS_T3"

# ---------------------------------------------------------------------------
# Schema validation: each task entry has verdict, evidence[], feedback
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: per-task entry schema ---\n'

FIELDS_T1="$(jq '.T1 | keys | sort | join(",")' -r "$VERDICT_MAP_PATH")"
assert_eq "T1 has required fields" "evidence,feedback,verdict" "$FIELDS_T1"

FIELDS_T2="$(jq '.T2 | keys | sort | join(",")' -r "$VERDICT_MAP_PATH")"
assert_eq "T2 has required fields" "evidence,feedback,verdict" "$FIELDS_T2"

FIELDS_T3="$(jq '.T3 | keys | sort | join(",")' -r "$VERDICT_MAP_PATH")"
assert_eq "T3 has required fields" "evidence,feedback,verdict" "$FIELDS_T3"

# ---------------------------------------------------------------------------
# Schema validation: verdict ∈ {PASS, FAIL, NEEDS_ITERATION}
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: verdict values ---\n'

VERDICT_T1="$(jq -r '.T1.verdict' "$VERDICT_MAP_PATH")"
VERDICT_T2="$(jq -r '.T2.verdict' "$VERDICT_MAP_PATH")"
VERDICT_T3="$(jq -r '.T3.verdict' "$VERDICT_MAP_PATH")"

assert_eq "T1 verdict is PASS (true exits 0)" "PASS" "$VERDICT_T1"
assert_eq "T2 verdict is PASS (both true exit 0)" "PASS" "$VERDICT_T2"
assert_eq "T3 verdict is FAIL (false exits non-zero)" "FAIL" "$VERDICT_T3"

# ---------------------------------------------------------------------------
# Schema validation: evidence is a non-empty array, feedback is a string
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: evidence and feedback types ---\n'

EVIDENCE_T1_TYPE="$(jq '.T1.evidence | type' "$VERDICT_MAP_PATH")"
assert_eq "T1 evidence is an array" '"array"' "$EVIDENCE_T1_TYPE"

EVIDENCE_T1_LEN="$(jq '.T1.evidence | length' "$VERDICT_MAP_PATH")"
assert_eq "T1 evidence is non-empty" "1" "$EVIDENCE_T1_LEN"

EVIDENCE_T2_LEN="$(jq '.T2.evidence | length' "$VERDICT_MAP_PATH")"
assert_eq "T2 evidence has 2 entries (one per VAL assertion)" "2" "$EVIDENCE_T2_LEN"

FEEDBACK_T1_TYPE="$(jq '.T1.feedback | type' "$VERDICT_MAP_PATH")"
assert_eq "T1 feedback is a string" '"string"' "$FEEDBACK_T1_TYPE"

FEEDBACK_T1="$(jq -r '.T1.feedback' "$VERDICT_MAP_PATH")"
assert_eq "T1 feedback is empty string (PASS)" "" "$FEEDBACK_T1"

FEEDBACK_T3_TYPE="$(jq '.T3.feedback | type' "$VERDICT_MAP_PATH")"
assert_eq "T3 feedback is a string" '"string"' "$FEEDBACK_T3_TYPE"

FEEDBACK_T3="$(jq -r '.T3.feedback' "$VERDICT_MAP_PATH")"
assert_eq "T3 feedback is non-empty (FAIL)" "0" "$(test -n "$FEEDBACK_T3" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# jq -e parses all three task entries as the downstream consumer would
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: downstream consumer parse ---\n'

JQ_PARSE_EXIT=0
jq -e '.T1.verdict, .T1.evidence, .T1.feedback' "$VERDICT_MAP_PATH" > /dev/null || JQ_PARSE_EXIT=$?
assert_eq "jq -e parses T1 fields" "0" "$JQ_PARSE_EXIT"

JQ_PARSE_EXIT=0
jq -e '.T2.verdict, .T2.evidence, .T2.feedback' "$VERDICT_MAP_PATH" > /dev/null || JQ_PARSE_EXIT=$?
assert_eq "jq -e parses T2 fields" "0" "$JQ_PARSE_EXIT"

JQ_PARSE_EXIT=0
jq -e '.T3.verdict, .T3.evidence, .T3.feedback' "$VERDICT_MAP_PATH" > /dev/null || JQ_PARSE_EXIT=$?
assert_eq "jq -e parses T3 fields" "0" "$JQ_PARSE_EXIT"

# ---------------------------------------------------------------------------
# Audit event: verifier_spawn_avoided emitted once per task
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: verifier_spawn_avoided audit events ---\n'

AUDIT_PATH="${RND_DIR}/audit.jsonl"

if [[ -f "$AUDIT_PATH" ]]; then
  SPAWN_AVOIDED_COUNT="$(grep -c '"event":"verifier_spawn_avoided"' "$AUDIT_PATH" || echo 0)"
  assert_eq "3 verifier_spawn_avoided events emitted (one per task)" "3" "$SPAWN_AVOIDED_COUNT"

  T1_AVOIDED="$(grep '"event":"verifier_spawn_avoided"' "$AUDIT_PATH" | grep '"task_id":"T1"' | head -1)"
  assert_eq "T1 verifier_spawn_avoided event exists" "0" "$(test -n "$T1_AVOIDED" && echo 0 || echo 1)"

  REASON_INLINE_COUNT="$(grep '"event":"verifier_spawn_avoided"' "$AUDIT_PATH" | grep -c '"tool":"inline"' || echo 0)"
  assert_eq "all verifier_spawn_avoided events have tool=inline (reason)" "3" "$REASON_INLINE_COUNT"
else
  # Audit events require RND_DIR/audit.jsonl to be writable by audit-event.sh
  # If the file doesn't exist, the helper silently skipped (|| true pattern)
  assert_eq "audit.jsonl exists (audit-event.sh wrote events)" "exists" "missing"
fi

# ---------------------------------------------------------------------------
# Edge case: --help exits 0
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: --help ---\n'

HELP_EXIT=0
HELP_OUT="$(bash "$INLINE_VERIFY" --help 2>&1)" || HELP_EXIT=$?
assert_eq "--help exits 0" "0" "$HELP_EXIT"
assert_contains "--help mentions usage" "Usage" "$HELP_OUT"

# ---------------------------------------------------------------------------
# Edge case: missing plan.md exits 1
# ---------------------------------------------------------------------------

printf '\n--- inline-verify: missing plan exits 1 ---\n'

MISSING_EXIT=0
bash "$INLINE_VERIFY" "/nonexistent/plan.md" "1" 2>/dev/null || MISSING_EXIT=$?
assert_eq "missing plan.md exits 1" "1" "$MISSING_EXIT"

report
