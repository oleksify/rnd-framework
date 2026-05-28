#!/usr/bin/env bash
# tests/outside-view-planner.test.sh — Content and additive-only diff tests
# for the outside-view consumer instruction added to agents/rnd-planner.md.
# Usage: bash tests/outside-view-planner.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

PLANNER="${PLUGIN_ROOT}/agents/rnd-planner.md"
PLANNER_BEFORE="${PLUGIN_ROOT}/tests/fixtures/rnd-planner.before.md"

# ---------------------------------------------------------------------------
# M4.planner.agent-prompt-mentions-outside-view
# rnd-planner.md names the "## Outside View (Reference Class)" heading and
# instructs the agent to apply it as a calibration anchor (not a license).
# ---------------------------------------------------------------------------

printf '\n--- agent-prompt-mentions-outside-view: content ---\n'

assert_eq \
  "rnd-planner.md references '## Outside View (Reference Class)' literal string" \
  "pass" \
  "$(grep -qF '## Outside View (Reference Class)' "$PLANNER" && printf pass || printf fail)"

assert_eq \
  "rnd-planner.md contains 'calibration anchor' phrase" \
  "pass" \
  "$(grep -qE 'calibration anchor' "$PLANNER" && printf pass || printf fail)"

assert_eq \
  "rnd-planner.md contains 'not a license' phrase" \
  "pass" \
  "$(grep -qiE 'not a license' "$PLANNER" && printf pass || printf fail)"

# ---------------------------------------------------------------------------
# Additive-only check: the baseline (before) file must be a strict subset of
# the new file — no existing lines were removed.
# ---------------------------------------------------------------------------

printf '\n--- agent-prompt-mentions-outside-view: additive-only diff ---\n'

assert_eq \
  "baseline tests/fixtures/rnd-planner.before.md exists" \
  "pass" \
  "$([ -f "$PLANNER_BEFORE" ] && printf pass || printf fail)"

if [[ -f "$PLANNER_BEFORE" ]]; then
  # diff -u: lines beginning with '-' (removals from old) must not appear.
  # Lines like '--- agents/...' (diff header) are excluded by the path filter.
  removal_count="$(diff -u "$PLANNER_BEFORE" "$PLANNER" | grep -c '^-[^-]' || true)"

  assert_eq \
    "diff shows no removals from existing content (additive-only)" \
    "0" \
    "$removal_count"
fi

# ---------------------------------------------------------------------------
report
