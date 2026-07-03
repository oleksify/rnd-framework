#!/usr/bin/env bash
# tests/self-fail-gap-coalesce.test.sh
# Regression test for the NULL-leak fix in lib/stats/self_fail_vs_verdict_gap.sql.
# A builder_self_assessment record carrying NEITHER build_status NOR self_verdict
# must collapse to self_fail = false (via the 3rd COALESCE arg), not NULL —
# otherwise `self_fail <> verifier_fail` evaluates to NULL and the row is
# silently dropped from gap_count.
#
# Revert-proof: without the `, false` third COALESCE arg, self_fail is NULL for
# the fixture row and gap_count is 0 instead of 1.
#
# Usage: bash tests/self-fail-gap-coalesce.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

SQL="${SCRIPT_DIR}/../lib/stats/self_fail_vs_verdict_gap.sql"

if ! command -v duckdb >/dev/null 2>&1; then
  printf 'SKIP: duckdb not available\n'
  exit 0
fi

RND_ROOT="$(mktemp -d)"
trap 'rm -rf "$RND_ROOT"' EXIT

SLUG="testslug-deadbeef"
SESS="20260101-120000-abcd"
SESSION_DIR="${RND_ROOT}/${SLUG}/branches/main/sessions/${SESS}"
mkdir -p "$SESSION_DIR"

# Builder self-assessment for (SESS, M1.T01.x) with NEITHER build_status NOR
# self_verdict — the exact NULL-both case the fix guards.
printf '%s\n' \
  '{"event":"builder_self_assessment","session_id":"'"$SESS"'","task_id":"M1.T01.x","timestamp":"2026-01-01T00:00:00Z"}' \
  > "${SESSION_DIR}/audit.jsonl"

# Verifier verdict for the SAME (session, task): non-PASS → verifier_fail = true.
printf '%s\n' \
  '{"session_id":"'"$SESS"'","task_id":"M1.T01.x","verdict":"NEEDS_ITERATION","timestamp":"2026-01-01T00:00:01Z"}' \
  > "${RND_ROOT}/${SLUG}/calibration.jsonl"

# Run the view from the .rnd root and read gap_count.
gap_count="$(
  cd "$RND_ROOT" \
    && RND_DOGFOOD_SLUGS="" duckdb -csv -noheader \
         -c ".read ${SQL}" \
         -c "SELECT gap_count FROM self_fail_vs_verdict_gap" 2>/dev/null
)"

printf '%s\n' '--- self_fail gap: NULL-both record counts as a gap (false, not NULL) ---'
assert_eq "neither-field record collapses to self_fail=false and is counted in gap_count" \
  "1" "$gap_count"

# ---------------------------------------------------------------------------
report
