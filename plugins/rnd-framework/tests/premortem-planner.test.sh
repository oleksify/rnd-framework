#!/usr/bin/env bash
# tests/premortem-planner.test.sh — Content-presence tests for premortem integration in rnd-planner.md
# Usage: bash tests/premortem-planner.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

AGENT="${PLUGIN_ROOT}/agents/rnd-planner.md"
content="$(cat "$AGENT")"

# ---------------------------------------------------------------------------
# Read instruction (M2.planner.reads-premortem-md)
# ---------------------------------------------------------------------------
printf '\n--- rnd-planner: premortem.md read instruction ---\n'

assert_contains "process step references premortem.md artifact" \
  "premortem.md" "$content"

assert_contains "process step uses read/consume verb near premortem.md" \
  "read" "$content"

# ---------------------------------------------------------------------------
# Premortem Responses output requirement (M2.planner.writes-premortem-responses)
# ---------------------------------------------------------------------------
printf '\n--- rnd-planner: Premortem Responses output requirement ---\n'

assert_contains "protocol.md template requires Premortem Responses section" \
  "## Premortem Responses" "$content"

assert_contains "requires one entry per FM<k>" \
  "FM<k>" "$content"

assert_contains "requires Addressed marker" \
  "Addressed" "$content"

assert_contains "requires Dismissed marker" \
  "Dismissed" "$content"

# ---------------------------------------------------------------------------
# Graceful absence clause (M2.planner.graceful-when-absent)
# ---------------------------------------------------------------------------
printf '\n--- rnd-planner: graceful-absence clause ---\n'

assert_contains "states action when premortem.md does not exist" \
  "does not exist" "$content"

assert_contains "states planner proceeds normally when absent" \
  "proceed" "$content"

report
