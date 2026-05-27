#!/usr/bin/env bash
# tests/premortem-wiring.test.sh — Content and ordering tests for the
# premortem fan-out pre-step wired into Phase 1 of commands/rnd-start.md.
# Usage: bash tests/premortem-wiring.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

RND_START="${PLUGIN_ROOT}/commands/rnd-start.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_grep() {
  local desc="$1" pattern="$2" file="$3"
  assert_eq "$desc" "pass" "$(grep -qiE "$pattern" "$file" && printf pass || printf fail)"
}

# Return the first line number matching a pattern (empty string if none).
first_line() {
  grep -n "$1" "$2" | head -1 | cut -d: -f1
}

# ---------------------------------------------------------------------------
# Phase 1 pre-step: content presence
# ---------------------------------------------------------------------------

printf '\n--- rnd-start Phase 1: premortem fan-out content ---\n'

assert_grep \
  "Phase 1 mentions general-purpose agent type" \
  "general-purpose" \
  "$RND_START"

assert_grep \
  "Phase 1 mentions haiku model" \
  "haiku" \
  "$RND_START"

assert_grep \
  "Phase 1 references premortem artifact or skill" \
  "premortem" \
  "$RND_START"

assert_grep \
  "Phase 1 contains premortem pre-step heading" \
  "Phase 1 pre-step.*[Pp]remortem" \
  "$RND_START"

# ---------------------------------------------------------------------------
# Ordering: premortem.md Write precedes rnd-planner spawn
# ---------------------------------------------------------------------------

printf '\n--- rnd-start Phase 1: premortem.md write before planner spawn ---\n'

premortem_write_line="$(first_line 'premortem\.md' "$RND_START")"
planner_spawn_line="$(first_line 'subagent_type.*rnd-framework:rnd-planner' "$RND_START")"

assert_eq \
  "premortem.md reference line found" \
  "pass" \
  "$([ -n "$premortem_write_line" ] && printf pass || printf fail)"

assert_eq \
  "rnd-planner spawn line found" \
  "pass" \
  "$([ -n "$planner_spawn_line" ] && printf pass || printf fail)"

assert_eq \
  "premortem.md reference precedes rnd-planner spawn" \
  "pass" \
  "$([ "${premortem_write_line:-0}" -lt "${planner_spawn_line:-0}" ] && printf pass || printf fail)"

# ---------------------------------------------------------------------------
# emit: premortem-emit.sh invocation present
# ---------------------------------------------------------------------------

printf '\n--- rnd-start Phase 1: premortem-emit.sh invocation ---\n'

assert_grep \
  "premortem-emit.sh is invoked in Phase 1" \
  "premortem-emit\.sh" \
  "$RND_START"

# ---------------------------------------------------------------------------
# Planner spawn prompt references premortem.md
# ---------------------------------------------------------------------------

printf '\n--- rnd-start Phase 1: planner prompt references premortem.md ---\n'

assert_grep \
  "planner spawn prompt includes premortem.md input" \
  'premortem.*premortem\.md|premortem\.md.*premortem' \
  "$RND_START"

# ---------------------------------------------------------------------------
report
