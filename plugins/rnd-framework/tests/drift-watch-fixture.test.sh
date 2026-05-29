#!/usr/bin/env bash
# Fixture reproduction test: runs drift_watch.sql from lib/stats/fixtures/ and
# asserts the output matches the EXPECTED.md documented values, including
# a non-NULL/non-nan slope row at the full 10-row window.
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
  printf 'SKIP drift-watch-fixture: duckdb not found on PATH\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Run the view and capture CSV output
# ---------------------------------------------------------------------------

RUN_OUTPUT="$(
  cd "$FIXTURES_DIR" && \
  RND_DOGFOOD_SLUGS="claude-130cb64f" duckdb -csv \
    -c ".read ../drift_watch.sql" \
    -c "SELECT segment, session_ordinal, session_id, iter_metric, replan_count, iter_slope, replan_slope, window_n FROM drift_watch ORDER BY segment, session_ordinal" \
    2>/dev/null
)"

RUN_EXIT=$?

# ---------------------------------------------------------------------------
# Criterion (a): the view exits 0
# ---------------------------------------------------------------------------

printf '%s\n' '--- drift_watch fixture: view exits 0 ---'

HOOK_EXIT=$RUN_EXIT
assert_exit_code "drift_watch view exits 0 against committed fixtures" 0

# ---------------------------------------------------------------------------
# Criterion (b): at least one row has window_n=10 with non-NULL, non-nan slopes
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- drift_watch fixture: full-window row exists (window_n=10, non-nan slopes) ---'

FULL_WINDOW_ROW="$(printf '%s\n' "$RUN_OUTPUT" | grep ',10$' | head -1 || true)"

assert_contains "output contains a window_n=10 row" ",10" "$FULL_WINDOW_ROW"
assert_contains "full-window row has non-nan iter_slope" "-0.0787878787878788" "$FULL_WINDOW_ROW"
assert_contains "full-window row has non-nan replan_slope" "-0.024242424242424235" "$FULL_WINDOW_ROW"

# ---------------------------------------------------------------------------
# Criterion (c): CONTENT-LEVEL — exact values for the full-window row (ordinal 10, s-df-9)
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- drift_watch fixture: exact slope values for ordinal 10 (s-df-9) ---'

EXPECTED_ROW="dogfood,10,s-df-9,1.0,0,-0.0787878787878788,-0.024242424242424235,10"

ACTUAL_ROW="$(printf '%s\n' "$RUN_OUTPUT" | grep 'dogfood,10,' | head -1 || true)"

assert_eq "dogfood ordinal-10 row matches EXPECTED.md exactly" "$EXPECTED_ROW" "$ACTUAL_ROW"

# ---------------------------------------------------------------------------
# Cross-check: feature segment max window_n = 2 (no full-window row)
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- drift_watch fixture: feature segment max window_n = 2 ---'

FEATURE_MAX_WINDOW="$(printf '%s\n' "$RUN_OUTPUT" | grep '^feature,' | awk -F',' '{print $NF}' | sort -n | tail -1 || true)"

assert_eq "feature segment max window_n = 2 (no full-window row)" "2" "$FEATURE_MAX_WINDOW"

# ---------------------------------------------------------------------------
# Cross-check: dogfood ordinal 1 (s-df-hist) has nan slopes
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- drift_watch fixture: ordinal 1 has nan slopes ---'

ORDINAL_1_ROW="$(printf '%s\n' "$RUN_OUTPUT" | grep 'dogfood,1,' | head -1 || true)"

assert_eq "dogfood ordinal-1 row (s-df-hist, pre-window) matches EXPECTED.md" \
  "dogfood,1,s-df-hist,0.0,0,nan,nan,1" "$ORDINAL_1_ROW"

# ---------------------------------------------------------------------------
report
