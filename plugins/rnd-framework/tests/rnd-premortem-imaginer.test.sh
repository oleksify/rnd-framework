#!/usr/bin/env bash
# Tests: rnd-premortem-imaginer agent is correctly wired as a restricted-tool spawn target.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/test-helpers.sh"

AGENT_FILE="${PLUGIN_DIR}/agents/rnd-premortem-imaginer.md"
RND_START="${PLUGIN_DIR}/commands/rnd-start.md"
PREMORTEM_SKILL="${PLUGIN_DIR}/skills/rnd-premortem/SKILL.md"

frontmatter_of() {
  awk '/^---$/{count++; if(count==2) exit} count==1{print}' "$1"
}

assert_file_nonempty() {
  local desc="$1" path="$2"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ -s "$path" ]]; then
    printf '  PASS  %s\n' "$desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s (path=%s)\n' "$desc" "$path"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_frontmatter_line() {
  local desc="$1" path="$2" regex="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if frontmatter_of "$path" | grep -qE "$regex"; then
    printf '  PASS  %s\n' "$desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s (regex=%s)\n' "$desc" "$regex"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_not_in_files() {
  local desc="$1" needle="$2"; shift 2
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -lF "$needle" "$@" >/dev/null 2>&1; then
    printf '  FAIL  %s (needle=%s)\n' "$desc" "$needle"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    printf '  PASS  %s\n' "$desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
}

printf '\n--- rnd-premortem-imaginer agent: existence and frontmatter ---\n'

assert_file_nonempty \
  "rnd-premortem-imaginer.md exists and is non-empty" \
  "$AGENT_FILE"

assert_frontmatter_line \
  "frontmatter declares 'tools: []' (explicit empty list)" \
  "$AGENT_FILE" \
  '^tools:[[:space:]]*\[\]$'

assert_frontmatter_line \
  "frontmatter declares 'model: haiku'" \
  "$AGENT_FILE" \
  '^model:[[:space:]]*haiku$'

printf '\n--- premortem fan-out wiring ---\n'

assert_not_in_files \
  "'general-purpose' residue absent from rnd-start.md and premortem/SKILL.md" \
  'general-purpose' \
  "$RND_START" "$PREMORTEM_SKILL"

assert_contains \
  "rnd-start.md references 'rnd-premortem-imaginer'" \
  'rnd-premortem-imaginer' \
  "$(cat "$RND_START")"

report
