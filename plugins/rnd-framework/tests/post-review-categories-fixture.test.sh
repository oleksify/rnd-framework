#!/usr/bin/env bash
# Fixture reproduction test: runs post_review_categories.sql from lib/stats/fixtures/
# and asserts the output matches the EXPECTED.md documented values, including:
#   - categorized finding rows bucketed correctly by category
#   - legacy rows without a category bucketed as 'uncategorized'
#   - theory-loss share (architecture+kiss / categorized findings)
#
# Requires: bash 3.2+, duckdb (SKIPs gracefully if duckdb is absent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${SCRIPT_DIR}/.."
FIXTURES_DIR="${PLUGIN_ROOT}/lib/stats/fixtures"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Skip if duckdb is not on PATH
# ---------------------------------------------------------------------------

if ! command -v duckdb >/dev/null 2>&1; then
  printf 'SKIP post-review-categories-fixture: duckdb not found on PATH\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Run the view and capture CSV output
# ---------------------------------------------------------------------------

VIEW_OUTPUT="$(
  cd "$FIXTURES_DIR" && \
  RND_DOGFOOD_SLUGS="claude-130cb64f" duckdb -csv \
    -c ".read ../post_review_categories.sql" \
    -c "SELECT * FROM post_review_categories ORDER BY segment, category" \
    2>/dev/null
)"

VIEW_EXIT=$?

# ---------------------------------------------------------------------------
# Criterion (a): the view exits 0
# ---------------------------------------------------------------------------

printf '%s\n' '--- post_review_categories fixture: view exits 0 ---'

HOOK_EXIT=$VIEW_EXIT
assert_exit_code "post_review_categories view exits 0" 0

# ---------------------------------------------------------------------------
# Criterion (b): categorized finding rows appear with correct counts
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- post_review_categories fixture: categorized rows ---'

ARCH_ROW="$(printf '%s\n' "$VIEW_OUTPUT" | grep 'dogfood,architecture,' | head -1 || true)"
CORR_ROW="$(printf '%s\n' "$VIEW_OUTPUT" | grep 'dogfood,correctness,' | head -1 || true)"
KISS_ROW="$(printf '%s\n' "$VIEW_OUTPUT" | grep 'dogfood,kiss,' | head -1 || true)"

assert_eq "dogfood/architecture finding_count = 1" "dogfood,architecture,1" "$ARCH_ROW"
assert_eq "dogfood/correctness finding_count = 1"  "dogfood,correctness,1"  "$CORR_ROW"
assert_eq "dogfood/kiss finding_count = 1"         "dogfood,kiss,1"         "$KISS_ROW"

STYLE_ROW="$(printf '%s\n' "$VIEW_OUTPUT" | grep 'feature,style,' | head -1 || true)"
assert_eq "feature/style finding_count = 1" "feature,style,1" "$STYLE_ROW"

# ---------------------------------------------------------------------------
# Criterion (c): legacy rows without category bucket as 'uncategorized'
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- post_review_categories fixture: uncategorized bucket ---'

UNCAT_DOG="$(printf '%s\n' "$VIEW_OUTPUT" | grep 'dogfood,uncategorized,' | head -1 || true)"
UNCAT_FEA="$(printf '%s\n' "$VIEW_OUTPUT" | grep 'feature,uncategorized,' | head -1 || true)"

assert_eq "dogfood legacy rows → uncategorized bucket, count = 2" "dogfood,uncategorized,2" "$UNCAT_DOG"
assert_eq "feature legacy row → uncategorized bucket, count = 1"  "feature,uncategorized,1" "$UNCAT_FEA"

# Clean rows (review_found=false) must NOT appear as findings
CLEAN_ROW_COUNT="$(printf '%s\n' "$VIEW_OUTPUT" | grep -c 'dogfood,' || true)"
assert_eq "dogfood has exactly 4 category rows (arch, correctness, kiss, uncategorized)" "4" "$CLEAN_ROW_COUNT"

# ---------------------------------------------------------------------------
# Criterion (d): theory-loss share matches hand-computed values
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- post_review_categories fixture: theory-loss share ---'

SHARE_OUTPUT="$(
  cd "$FIXTURES_DIR" && \
  RND_DOGFOOD_SLUGS="claude-130cb64f" duckdb -csv \
    -c ".read ../post_review_categories.sql" \
    -c "SELECT segment,
          COALESCE(sum(finding_count) FILTER (WHERE category IN ('architecture','kiss')), 0) AS theory_loss_count,
          COALESCE(sum(finding_count) FILTER (WHERE category != 'uncategorized'), 0)         AS categorized_count,
          round(
            COALESCE(sum(finding_count) FILTER (WHERE category IN ('architecture','kiss')), 0) * 1.0
            / NULLIF(COALESCE(sum(finding_count) FILTER (WHERE category != 'uncategorized'), 0), 0),
            4
          ) AS theory_loss_share
        FROM post_review_categories
        GROUP BY segment
        ORDER BY segment" \
    2>/dev/null
)"

DOG_SHARE_ROW="$(printf '%s\n' "$SHARE_OUTPUT" | grep '^dogfood,' | head -1 || true)"
FEA_SHARE_ROW="$(printf '%s\n' "$SHARE_OUTPUT" | grep '^feature,' | head -1 || true)"

assert_eq "dogfood theory-loss share row matches EXPECTED.md" "dogfood,2,3,0.6667" "$DOG_SHARE_ROW"
assert_eq "feature theory-loss share row matches EXPECTED.md" "feature,0,1,0.0"    "$FEA_SHARE_ROW"

# ---------------------------------------------------------------------------
# Criterion (e): view is isolated — post_review_findings still renders cleanly
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- post_review_findings still exits 0 after fixture extension ---'

FINDINGS_EXIT=0
cd "$FIXTURES_DIR" && \
  RND_DOGFOOD_SLUGS="claude-130cb64f" duckdb -csv \
    -c ".read ../post_review_findings.sql" \
    -c "SELECT * FROM post_review_findings ORDER BY segment, shape" \
    >/dev/null 2>&1 || FINDINGS_EXIT=$?

HOOK_EXIT=$FINDINGS_EXIT
assert_exit_code "post_review_findings view still exits 0" 0

# ---------------------------------------------------------------------------
report
