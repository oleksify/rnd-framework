#!/usr/bin/env bash
# End-to-end test: fires all three real producers against a synthetic .rnd
# fixture tree and asserts the DuckDB views return non-empty results.
#
# Load-bearing checks:
#  - shape_distribution returns ≥1 row (shape facts landed in audit.jsonl)
#  - per_shape_fail_rate exits 0 and returns ≥1 row (JOIN across casing matched)
#  - self_fail_vs_verdict_gap exits 0 and returns ≥1 row (JOIN matched)
#  - Idempotency: firing calibration-producer twice does not inflate view counts
#
# Requires: bash 3.2+, jq, duckdb (SKIPs gracefully if duckdb is absent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${SCRIPT_DIR}/.."

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Skip if duckdb is not on PATH
# ---------------------------------------------------------------------------

if ! command -v duckdb >/dev/null 2>&1; then
  printf 'SKIP phase0-producers-e2e: duckdb not found on PATH\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Fixture layout
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SLUG="claude-130cb64f"
SESSION_ID="20260527-100000-e2etest"
RND_ROOT="${TMP_DIR}/.rnd"
SLUG_ROOT="${RND_ROOT}/${SLUG}"
SESSION="${SLUG_ROOT}/branches/main/sessions/${SESSION_ID}"
BUILDS="${SESSION}/builds"
VERIFICATIONS="${SESSION}/verifications"

mkdir -p "$BUILDS" "$VERIFICATIONS"

TASK_A="M2.T01.shared-helpers"
TASK_B="M2.T02.producers"
ASSERT_A1="M2.helper.extracts-session-id"
ASSERT_A2="M2.helper.assertion-parser-lifted"
ASSERT_B1="M2.prod.emits-shape-facts"

CONTRACT="${SESSION}/validation-contract.md"
FEATURES="${SESSION}/features.json"
AUDIT="${SESSION}/audit.jsonl"
VERDICT_MAP="${VERIFICATIONS}/wave-1-verdict-map.json"
CALIB="${SLUG_ROOT}/calibration.jsonl"

# ---------------------------------------------------------------------------
# Helper: fire a hook with a Write tool_input; sets HOOK_EXIT for assert_exit_code.
# ---------------------------------------------------------------------------

run_hook() {
  local hook="$1"
  local file_path="$2"

  HOOK_EXIT=0
  printf '%s' "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"${file_path}\"}}" \
    | env -i PATH="$PATH" HOME="$HOME" \
        PLUGIN_ROOT="$PLUGIN_ROOT" \
        "$hook" >/dev/null 2>&1 || HOOK_EXIT=$?
}

# Run a duckdb view and return the SELECT count(*) integer.
# Uses -csv mode so the output is a plain number on the second line (after the header).
# Returns "0" if the query fails (so assertion catches it).
duckdb_count() {
  local view_sql="$1"
  local view_name="$2"

  (
    cd "$RND_ROOT"
    duckdb -csv \
      -c ".read ${PLUGIN_ROOT}/lib/stats/${view_sql}" \
      -c "SELECT count(*) AS n FROM ${view_name}" \
      2>/dev/null | tail -1
  ) || echo 0
}

# Run a full duckdb view invocation and capture exit code without aborting test.
duckdb_exit() {
  local view_sql="$1"
  local view_name="$2"
  local exit_code=0

  (
    set +e
    cd "$RND_ROOT"
    duckdb \
      -c ".read ${PLUGIN_ROOT}/lib/stats/${view_sql}" \
      -c "SELECT count(*) FROM ${view_name}" \
      >/dev/null 2>&1
    exit $?
  ) || exit_code=$?

  printf '%s' "$exit_code"
}

# ---------------------------------------------------------------------------
# Step A: write contract, fire shape-producer — features.json absent → 0 lines.
# ---------------------------------------------------------------------------

printf '%s\n' '--- e2e: contract written before features.json → 0 shape facts ---'

printf '%s' \
'# Validation Contract

### M2.helper.extracts-session-id
Extracts session id from artifact path.
Shape: wiring
Confidence: high

### M2.helper.assertion-parser-lifted
Parser lifted to shared location.
Shape: pure-refactor
Confidence: high

### M2.prod.emits-shape-facts
Producer emits one fact per assertion.
Shape: wiring
Confidence: medium
' > "$CONTRACT"

rm -f "$AUDIT"

run_hook "${PLUGIN_ROOT}/hooks/shape-producer.sh" "$CONTRACT"

assert_exit_code "contract-only → exit 0 (hook always returns 0)" 0

SHAPE_AFTER_CONTRACT="$(grep -c '"event":"assertion_shape"' "$AUDIT" 2>/dev/null || echo 0)"
assert_eq "contract-only → 0 shape facts (no wrong-task fallback)" "0" "$SHAPE_AFTER_CONTRACT"

# ---------------------------------------------------------------------------
# Step B: write features.json, fire shape-producer — both present → 3 lines.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: features.json written second → 3 shape facts with owning task_id ---'

printf '%s' \
"{
  \"tasks\": [
    {
      \"id\": \"${TASK_A}\",
      \"assertionIds\": [\"${ASSERT_A1}\", \"${ASSERT_A2}\"]
    },
    {
      \"id\": \"${TASK_B}\",
      \"assertionIds\": [\"${ASSERT_B1}\"]
    }
  ]
}" > "$FEATURES"

rm -f "$AUDIT"

run_hook "${PLUGIN_ROOT}/hooks/shape-producer.sh" "$FEATURES"

assert_exit_code "features.json trigger → exit 0" 0

SHAPE_COUNT="$(grep -c '"event":"assertion_shape"' "$AUDIT" 2>/dev/null || echo 0)"
assert_eq "both present, fired on features.json → 3 assertion_shape lines" "3" "$SHAPE_COUNT"

assert_contains "TASK_A assertion A1 has owning task_id" \
  "\"task_id\":\"${TASK_A}\"" \
  "$(grep "${ASSERT_A1}" "$AUDIT" 2>/dev/null || true)"

assert_contains "TASK_B assertion B1 has owning task_id" \
  "\"task_id\":\"${TASK_B}\"" \
  "$(grep "${ASSERT_B1}" "$AUDIT" 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Step C: write self-assessment for TASK_A, fire self-assessment-producer.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: self-assessment-producer fires → builder_self_assessment in audit ---'

ASSESS_PATH="${BUILDS}/${TASK_A}-self-assessment.md"

printf '%s' \
"# Self-Assessment: ${TASK_A}

All criteria met with HIGH confidence. No deviations. No unverified assumptions.
" > "$ASSESS_PATH"

run_hook "${PLUGIN_ROOT}/hooks/self-assessment-producer.sh" "$ASSESS_PATH"

assert_exit_code "self-assessment-producer → exit 0" 0

SA_LINE="$(grep '"event":"builder_self_assessment"' "$AUDIT" 2>/dev/null | head -1 || true)"

assert_contains "builder_self_assessment event landed in audit" \
  '"event":"builder_self_assessment"' "$SA_LINE"

assert_contains "builder_self_assessment task_id = TASK_A (snake_case)" \
  "\"task_id\":\"${TASK_A}\"" "$SA_LINE"

assert_contains "self_verdict = PASS (minimal form)" \
  '"self_verdict":"PASS"' "$SA_LINE"

# ---------------------------------------------------------------------------
# Step D: write verdict-map, fire calibration-producer.
# Task A: all-PASS → PASS (same task_id as shape fact + self-assessment).
# Task B: one FAIL → NEEDS_ITERATION.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: calibration-producer fires → records at slug-root calibration.jsonl ---'

printf '%s' \
"{
  \"${ASSERT_A1}\": {
    \"verdict\": \"PASS\",
    \"evidence\": [\"e1\"],
    \"feedback\": \"\",
    \"task_id\": \"${TASK_A}\"
  },
  \"${ASSERT_A2}\": {
    \"verdict\": \"PASS\",
    \"evidence\": [\"e2\"],
    \"feedback\": \"\",
    \"task_id\": \"${TASK_A}\"
  },
  \"${ASSERT_B1}\": {
    \"verdict\": \"FAIL\",
    \"evidence\": [\"e3\"],
    \"feedback\": \"failed\",
    \"task_id\": \"${TASK_B}\"
  }
}" > "$VERDICT_MAP"

rm -f "$CALIB"

run_hook "${PLUGIN_ROOT}/hooks/calibration-producer.sh" "$VERDICT_MAP"

assert_exit_code "calibration-producer → exit 0" 0

assert_eq "calibration.jsonl created at slug-root" \
  "1" "$([ -f "$CALIB" ] && echo 1 || echo 0)"

assert_eq "calibration.jsonl NOT in session dir" \
  "" "$([ -f "${SESSION}/calibration.jsonl" ] && echo exists || true)"

CALIB_COUNT_FIRST="$(grep -c '"task_id"' "$CALIB" 2>/dev/null || echo 0)"
assert_eq "2 verdict records for 2 tasks" "2" "$CALIB_COUNT_FIRST"

TASK_A_VERDICT="$(grep "\"${TASK_A}\"" "$CALIB" | jq -r '.verdict' 2>/dev/null || true)"
assert_eq "Task A (all-PASS) → verdict PASS" "PASS" "$TASK_A_VERDICT"

TASK_B_VERDICT="$(grep "\"${TASK_B}\"" "$CALIB" | jq -r '.verdict' 2>/dev/null || true)"
assert_eq "Task B (one FAIL) → verdict NEEDS_ITERATION" "NEEDS_ITERATION" "$TASK_B_VERDICT"

HAS_CAMEL="$(grep '"task_id"' "$CALIB" | wc -l | tr -d ' ')"
assert_eq "verdict records use snake_case task_id" "2" "$HAS_CAMEL"

# ---------------------------------------------------------------------------
# Step E: idempotency — fire calibration-producer a second time.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: idempotency — second calibration fire ---'

run_hook "${PLUGIN_ROOT}/hooks/calibration-producer.sh" "$VERDICT_MAP"

assert_exit_code "second calibration fire → exit 0" 0

CALIB_COUNT_SECOND="$(grep -c '"task_id"' "$CALIB" 2>/dev/null || echo 0)"
assert_eq "raw records ≥ first count after second fire (append-only)" \
  "1" "$([ "$CALIB_COUNT_SECOND" -ge "$CALIB_COUNT_FIRST" ] && echo 1 || echo 0)"

# ---------------------------------------------------------------------------
# Step F: run DuckDB views from the fixture .rnd root.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: shape_distribution returns ≥1 non-null-shape row ---'

SHAPE_DIST_COUNT="$(duckdb_count "shape_distribution.sql" "shape_distribution")"

assert_eq "shape_distribution count ≥ 1" \
  "1" "$([ "${SHAPE_DIST_COUNT:-0}" -ge 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: per_shape_fail_rate exits 0 and returns ≥1 row ---'

PER_SHAPE_EXIT="$(duckdb_exit "per_shape_fail_rate.sql" "per_shape_fail_rate")"
assert_eq "per_shape_fail_rate: exit 0 (no hard-error)" "0" "$PER_SHAPE_EXIT"

PER_SHAPE_COUNT="$(duckdb_count "per_shape_fail_rate.sql" "per_shape_fail_rate")"
assert_eq "per_shape_fail_rate count ≥ 1 (JOIN matched across casing)" \
  "1" "$([ "${PER_SHAPE_COUNT:-0}" -ge 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: self_fail_vs_verdict_gap exits 0 and returns ≥1 row ---'

GAP_EXIT="$(duckdb_exit "self_fail_vs_verdict_gap.sql" "self_fail_vs_verdict_gap")"
assert_eq "self_fail_vs_verdict_gap: exit 0 (no hard-error)" "0" "$GAP_EXIT"

GAP_COUNT="$(duckdb_count "self_fail_vs_verdict_gap.sql" "self_fail_vs_verdict_gap")"
assert_eq "self_fail_vs_verdict_gap count ≥ 1 (JOIN matched across casing)" \
  "1" "$([ "${GAP_COUNT:-0}" -ge 1 ] && echo 1 || echo 0)"

# ---------------------------------------------------------------------------
# Idempotency end-to-end: view count unchanged after second calibration fire.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: per_shape_fail_rate count unchanged after second calibration fire ---'

PER_SHAPE_COUNT_AFTER_SECOND="$(duckdb_count "per_shape_fail_rate.sql" "per_shape_fail_rate")"

assert_eq "per_shape_fail_rate count unchanged (QUALIFY dedup holds)" \
  "$PER_SHAPE_COUNT" "$PER_SHAPE_COUNT_AFTER_SECOND"

# ---------------------------------------------------------------------------
# Segment check: the claude-130cb64f slug resolves to 'dogfood'.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- e2e: segment = dogfood for claude-130cb64f slug ---'

SEGMENT="$(
  cd "$RND_ROOT" && RND_DOGFOOD_SLUGS="claude-130cb64f" duckdb -csv \
    -c ".read ${PLUGIN_ROOT}/lib/stats/shape_distribution.sql" \
    -c "SELECT segment FROM shape_distribution WHERE segment = 'dogfood' LIMIT 1" \
    2>/dev/null | tail -1 || true
)"

assert_eq "fixture slug resolves to dogfood segment" "dogfood" "$SEGMENT"

# ---------------------------------------------------------------------------
report
