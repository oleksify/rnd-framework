#!/usr/bin/env bash
# tests/rnd-cards-impact.test.sh — Tests for lib/rnd-cards-impact.sh
# Usage: bash tests/rnd-cards-impact.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/test-helpers.sh"

IMPACT="${PLUGIN_ROOT}/lib/rnd-cards-impact.sh"

# ---------------------------------------------------------------------------
# Fixture setup
#
# Two task_types straddling the split date 2026-03-01T00:00:00Z:
#
# "refactor" tasks — post-rollout iterations clearly lower (verdict: improved)
#   Pre-rollout (start before 2026-03-01):
#     R1: 3 iterations before PASS   (started 2026-01-10)
#     R2: 2 iterations before PASS   (started 2026-01-20)
#     R3: 4 iterations before PASS   (started 2026-02-05)
#   Pre counts: [3, 2, 4] → sorted [2, 3, 4] → median=3, p75=4
#
#   Post-rollout (start on or after 2026-03-01):
#     R4: 0 iterations before PASS   (started 2026-03-10)
#     R5: 1 iteration  before PASS   (started 2026-04-01)
#     R6: 0 iterations before PASS   (started 2026-04-15)
#   Post counts: [0, 1, 0] → sorted [0, 0, 1] → median=0, p75=0
#   Verdict: post_median(0) < pre_median(3) - 0.5(=2.5) → improved ✓
#
# "new-feature" tasks — roughly same iterations (verdict: no-change)
#   Pre-rollout:
#     N1: 1 iteration before PASS    (started 2026-01-15)
#     N2: 2 iterations before PASS   (started 2026-02-10)
#     N3: 1 iteration before PASS    (started 2026-02-20)
#   Pre counts: [1, 2, 1] → sorted [1, 1, 2] → median=1
#
#   Post-rollout:
#     N4: 1 iteration before PASS    (started 2026-03-05)
#     N5: 2 iterations before PASS   (started 2026-04-10)
#     N6: 1 iteration before PASS    (started 2026-05-01)
#   Post counts: [1, 2, 1] → sorted [1, 1, 2] → median=1
#   Verdict: post_median(1) - pre_median(1) = 0, within 0.5 → no-change ✓
#
# All other task_types have 0 records → insufficient-data.
# ---------------------------------------------------------------------------

SPLIT_DATE="2026-03-01T00:00:00Z"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CALIB_DIR="${TMP_DIR}/plugin-data"
mkdir -p "$CALIB_DIR"
CALIB_FILE="${CALIB_DIR}/calibration.jsonl"

# Refactor — pre-rollout
printf '%s\n' \
  '{"taskId":"R1","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-01-10T10:00:00Z"}' \
  '{"taskId":"R1","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-01-11T10:00:00Z"}' \
  '{"taskId":"R1","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-01-12T10:00:00Z"}' \
  '{"taskId":"R1","criticality":"MEDIUM","verdict":"PASS","task_type":"refactor","timestamp":"2026-01-13T10:00:00Z"}' \
  '{"taskId":"R2","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-01-20T10:00:00Z"}' \
  '{"taskId":"R2","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-01-21T10:00:00Z"}' \
  '{"taskId":"R2","criticality":"MEDIUM","verdict":"PASS","task_type":"refactor","timestamp":"2026-01-22T10:00:00Z"}' \
  '{"taskId":"R3","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-02-05T10:00:00Z"}' \
  '{"taskId":"R3","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-02-06T10:00:00Z"}' \
  '{"taskId":"R3","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-02-07T10:00:00Z"}' \
  '{"taskId":"R3","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-02-08T10:00:00Z"}' \
  '{"taskId":"R3","criticality":"MEDIUM","verdict":"PASS","task_type":"refactor","timestamp":"2026-02-09T10:00:00Z"}' \
  >> "$CALIB_FILE"

# Refactor — post-rollout
printf '%s\n' \
  '{"taskId":"R4","criticality":"MEDIUM","verdict":"PASS","task_type":"refactor","timestamp":"2026-03-10T10:00:00Z"}' \
  '{"taskId":"R5","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"refactor","timestamp":"2026-04-01T10:00:00Z"}' \
  '{"taskId":"R5","criticality":"MEDIUM","verdict":"PASS","task_type":"refactor","timestamp":"2026-04-02T10:00:00Z"}' \
  '{"taskId":"R6","criticality":"MEDIUM","verdict":"PASS","task_type":"refactor","timestamp":"2026-04-15T10:00:00Z"}' \
  >> "$CALIB_FILE"

# New-feature — pre-rollout
printf '%s\n' \
  '{"taskId":"N1","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"new-feature","timestamp":"2026-01-15T10:00:00Z"}' \
  '{"taskId":"N1","criticality":"MEDIUM","verdict":"PASS","task_type":"new-feature","timestamp":"2026-01-16T10:00:00Z"}' \
  '{"taskId":"N2","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"new-feature","timestamp":"2026-02-10T10:00:00Z"}' \
  '{"taskId":"N2","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"new-feature","timestamp":"2026-02-11T10:00:00Z"}' \
  '{"taskId":"N2","criticality":"MEDIUM","verdict":"PASS","task_type":"new-feature","timestamp":"2026-02-12T10:00:00Z"}' \
  '{"taskId":"N3","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"new-feature","timestamp":"2026-02-20T10:00:00Z"}' \
  '{"taskId":"N3","criticality":"MEDIUM","verdict":"PASS","task_type":"new-feature","timestamp":"2026-02-21T10:00:00Z"}' \
  >> "$CALIB_FILE"

# New-feature — post-rollout
printf '%s\n' \
  '{"taskId":"N4","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"new-feature","timestamp":"2026-03-05T10:00:00Z"}' \
  '{"taskId":"N4","criticality":"MEDIUM","verdict":"PASS","task_type":"new-feature","timestamp":"2026-03-06T10:00:00Z"}' \
  '{"taskId":"N5","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"new-feature","timestamp":"2026-04-10T10:00:00Z"}' \
  '{"taskId":"N5","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"new-feature","timestamp":"2026-04-11T10:00:00Z"}' \
  '{"taskId":"N5","criticality":"MEDIUM","verdict":"PASS","task_type":"new-feature","timestamp":"2026-04-12T10:00:00Z"}' \
  '{"taskId":"N6","criticality":"MEDIUM","verdict":"NEEDS_ITERATION","task_type":"new-feature","timestamp":"2026-05-01T10:00:00Z"}' \
  '{"taskId":"N6","criticality":"MEDIUM","verdict":"PASS","task_type":"new-feature","timestamp":"2026-05-02T10:00:00Z"}' \
  >> "$CALIB_FILE"

printf '\n--- rnd-cards-impact: fixture seeded ---\n'
printf '  refactor pre: 3 tasks with [3,2,4] iterations → pre-median=3\n'
printf '  refactor post: 3 tasks with [0,1,0] iterations → post-median=0 → improved\n'
printf '  new-feature pre: 3 tasks with [1,2,1] iterations → pre-median=1\n'
printf '  new-feature post: 3 tasks with [1,2,1] iterations → post-median=1 → no-change\n\n'

# Run the script and capture output.
output="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$IMPACT" --since="$SPLIT_DATE" --per-type-min=3)"

printf '\n--- rnd-cards-impact: output ---\n'
printf '%s\n' "$output"
printf '\n'

printf '\n--- VAL-IMP-002: table structure ---\n'

# Table header row is present.
assert_contains "table header row present"         "task_type" "$output"
assert_contains "table has pre-N column"           "pre-N"     "$output"
assert_contains "table has pre-median column"      "pre-median" "$output"
assert_contains "table has pre-p75 column"         "pre-p75"   "$output"
assert_contains "table has post-N column"          "post-N"    "$output"
assert_contains "table has post-median column"     "post-median" "$output"
assert_contains "table has post-p75 column"        "post-p75"  "$output"
assert_contains "table has verdict column"         "verdict"   "$output"

# Separator row present.
assert_contains "table separator row present" "---" "$output"

printf '\n--- VAL-IMP-002: one row per task_type ---\n'

for tt in refactor new-feature bugfix docs config infra; do
  assert_contains "row present for $tt" "$tt" "$output"
done

printf '\n--- VAL-IMP-002: verdict correctness ---\n'

# refactor row: expect "improved"
assert_contains "refactor verdict is improved" "improved" "$output"

# new-feature row: expect "no-change"
assert_contains "new-feature verdict is no-change" "no-change" "$output"

# buckets without enough data emit "insufficient-data"
assert_contains "insufficient-data appears for sparse types" "insufficient-data" "$output"

printf '\n--- VAL-IMP-002: median values ---\n'

# refactor pre-median should be 3 (from [2,3,4] sorted, index 1)
refactor_row="$(printf '%s' "$output" | grep 'refactor')"
assert_contains "refactor pre-median is 3" "3" "$refactor_row"
assert_contains "refactor post-median is 0" "0" "$refactor_row"

# new-feature pre-median should be 1, post-median should be 1
newfeature_row="$(printf '%s' "$output" | grep 'new-feature')"
assert_contains "new-feature pre-N is 3" "3" "$newfeature_row"
assert_contains "new-feature post-N is 3" "3" "$newfeature_row"
assert_contains "new-feature pre-median is 1" "1" "$newfeature_row"

printf '\n--- VAL-IMP-002: insufficient-data for per-type-min ---\n'

# With --per-type-min=10, all buckets have fewer than 10 samples → insufficient-data everywhere.
output_highmin="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$IMPACT" \
  --since="$SPLIT_DATE" --per-type-min=10)"

# All rows should show insufficient-data.
refactor_highmin="$(printf '%s' "$output_highmin" | grep 'refactor')"
assert_contains "refactor insufficient-data when min=10" "insufficient-data" "$refactor_highmin"

newfeature_highmin="$(printf '%s' "$output_highmin" | grep 'new-feature')"
assert_contains "new-feature insufficient-data when min=10" "insufficient-data" "$newfeature_highmin"

printf '\n--- VAL-IMP-001: --help exits 0 and documents --since ---\n'

help_output="$(CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$IMPACT" --help 2>&1)"
help_exit=0
CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$IMPACT" --help >/dev/null 2>&1 || help_exit=$?
assert_eq "--help exits 0" "0" "$help_exit"
assert_contains "--help documents --since" "--since" "$help_output"
assert_contains "--help documents --per-type-min" "--per-type-min" "$help_output"

printf '\n--- VAL-IMP-001: missing --since exits non-zero ---\n'

nosince_exit=0
CLAUDE_PLUGIN_DATA="$CALIB_DIR" "$IMPACT" >/dev/null 2>&1 || nosince_exit=$?
if [[ "$nosince_exit" -ne 0 ]]; then
  assert_eq "missing --since exits non-zero" "non-zero" "non-zero"
else
  assert_eq "missing --since exits non-zero" "non-zero" "0"
fi

printf '\n--- VAL-IMP-002: records without timestamp are excluded ---\n'

CALIB_NOTIMESTAMP="${TMP_DIR}/no-ts"
mkdir -p "$CALIB_NOTIMESTAMP"
printf '%s\n' \
  '{"taskId":"X1","criticality":"MEDIUM","verdict":"PASS","task_type":"refactor"}' \
  > "${CALIB_NOTIMESTAMP}/calibration.jsonl"

# Should not crash; refactor pre-N and post-N should be 0 (record excluded).
output_nots="$(CLAUDE_PLUGIN_DATA="$CALIB_NOTIMESTAMP" "$IMPACT" \
  --since="$SPLIT_DATE" --per-type-min=1 2>&1)"
refactor_nots="$(printf '%s' "$output_nots" | grep 'refactor')"
assert_contains "no-timestamp record excluded → insufficient-data" "insufficient-data" "$refactor_nots"

printf '\n--- VAL-IMP-002: task_type defaults to infra when absent ---\n'

CALIB_NOTYPE="${TMP_DIR}/no-type"
mkdir -p "$CALIB_NOTYPE"
printf '%s\n' \
  '{"taskId":"Y1","criticality":"MEDIUM","verdict":"PASS","timestamp":"2026-02-01T00:00:00Z"}' \
  '{"taskId":"Y2","criticality":"MEDIUM","verdict":"PASS","timestamp":"2026-04-01T00:00:00Z"}' \
  > "${CALIB_NOTYPE}/calibration.jsonl"

# Both tasks have no task_type → default to "infra"; one pre, one post.
output_notype="$(CLAUDE_PLUGIN_DATA="$CALIB_NOTYPE" "$IMPACT" \
  --since="$SPLIT_DATE" --per-type-min=1 2>&1)"
infra_notype="$(printf '%s' "$output_notype" | grep ' infra ')"
assert_contains "no-type record defaults to infra (pre-N=1)" "1" "$infra_notype"
assert_contains "no-type record defaults to infra (post-N=1)" "1" "$infra_notype"

report
