#!/usr/bin/env bash
# Smoke tests for the rnd-cleanup agent and skill files.
# Usage: bash tests/cleanup-agent.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="${SCRIPT_DIR}/.."
AGENT_FILE="${PLUGIN_DIR}/agents/rnd-cleanup.md"
SKILL_FILE="${PLUGIN_DIR}/skills/rnd-cleanup/SKILL.md"

PASS=0
FAIL=0

pass() {
  local name="$1"
  printf 'PASS  %s\n' "$name"
  PASS=$((PASS + 1))
}

fail() {
  local name="$1"
  local detail="$2"
  printf 'FAIL  %s — %s\n' "$name" "$detail"
  FAIL=$((FAIL + 1))
}

assert_file_exists() {
  local name="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    pass "$name"
  else
    fail "$name" "file not found: $path"
  fi
}

assert_file_contains() {
  local name="$1"
  local path="$2"
  local pattern="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    pass "$name"
  else
    fail "$name" "pattern '$pattern' not found in $path"
  fi
}

# ---------------------------------------------------------------------------
# Agent file tests
# ---------------------------------------------------------------------------

# 1. Agent file exists
assert_file_exists "agent file exists" "$AGENT_FILE"

# 2. Frontmatter: name: rnd-cleanup
assert_file_contains "frontmatter: name: rnd-cleanup" "$AGENT_FILE" "^name: rnd-cleanup"

# 3. Frontmatter: model: sonnet
assert_file_contains "frontmatter: model: sonnet" "$AGENT_FILE" "^model: sonnet"

# 4. Frontmatter: effort: medium
assert_file_contains "frontmatter: effort: medium" "$AGENT_FILE" "^effort: medium"

# 5. Body contains "dead function" detection keyword (dead functions / dead code)
assert_file_contains "body: dead functions keyword" "$AGENT_FILE" "[Dd]ead"

# 6. Body contains "orphan" keyword
assert_file_contains "body: orphan keyword" "$AGENT_FILE" "orphan"

# 7. Body contains "duplicate" keyword
assert_file_contains "body: duplicate keyword" "$AGENT_FILE" "duplicate"

# 8. Body contains "stale comment" keyword
assert_file_contains "body: stale comment keyword" "$AGENT_FILE" "stale comment"

# 9. Body contains a rollback keyword (git restore, git checkout, or git stash)
if grep -qE "git (restore|checkout|stash)" "$AGENT_FILE" 2>/dev/null; then
  pass "body: rollback keyword present"
else
  fail "body: rollback keyword present" "no 'git restore', 'git checkout', or 'git stash' found in $AGENT_FILE"
fi

# 10. Body contains $RND_DIR/cleanup/T path pattern
assert_file_contains 'body: $RND_DIR/cleanup/T path pattern' "$AGENT_FILE" 'RND_DIR/cleanup/T'

# ---------------------------------------------------------------------------
# Skill file tests
# ---------------------------------------------------------------------------

# 11. Skill file exists
assert_file_exists "skill file exists" "$SKILL_FILE"

# 12. Skill file mentions auto-tag / auto-commit avoidance (contains "auto")
assert_file_contains "skill: mentions 'auto' behavior" "$SKILL_FILE" "[Aa][Uu][Tt][Oo]"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
