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

# Passes when the extended regex does NOT match any line in the file.
assert_not_match() {
  local desc="$1" regex="$2" path="$3"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -qE "$regex" "$path"; then
    printf '  FAIL  %s (regex=%s)\n' "$desc" "$regex"
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

# The fan-out wiring lives in premortem/SKILL.md — no 'general-purpose' may leak
# there. rnd-start.md is intentionally NOT covered by this blanket check: it names
# 'general-purpose' in a prohibition ("Do NOT spawn the built-in Explore or
# general-purpose subagents"), which is correct guidance, not wiring residue.
assert_not_in_files \
  "'general-purpose' residue absent from premortem/SKILL.md" \
  'general-purpose' \
  "$PREMORTEM_SKILL"

# rnd-start.md must never wire 'general-purpose' as a spawn target — the substring
# is allowed only in prose, never as a subagent_type/spawn argument.
assert_not_match \
  "rnd-start.md does not wire 'general-purpose' as a spawn target" \
  'subagent_type[^[:alnum:]]*general-purpose' \
  "$RND_START"

assert_contains \
  "rnd-start.md references 'rnd-premortem-imaginer'" \
  'rnd-premortem-imaginer' \
  "$(cat "$RND_START")"

report
