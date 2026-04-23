#!/usr/bin/env bash
# Structural tests for bump.sh's claude plugin tag behavior.
# Does NOT run bump.sh live — source-level checks only (no side effects).
# Usage: bash tests/bump-plugin-tag.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP="${SCRIPT_DIR}/../lib/bump.sh"
SKILL="${SCRIPT_DIR}/../skills/rnd-bump/SKILL.md"

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
# bump.sh structural tests
# ---------------------------------------------------------------------------

# 1. bump.sh source contains "claude plugin tag" invocation
assert_file_contains "bump.sh: contains 'claude plugin tag'" "$BUMP" "claude plugin tag"

# 2. bump.sh source contains "command -v claude" PATH guard
assert_file_contains "bump.sh: contains 'command -v claude' PATH check" "$BUMP" "command -v claude"

# 3. A comment appears before the plugin tag block (described intent)
assert_file_contains "bump.sh: comment precedes plugin tag block" "$BUMP" "^#.*[Aa]uto.tag\|^#.*claude plugin tag\|^# --- Auto-tag"

# 4. Structural: PATH check occurs before the invocation line that calls claude plugin tag.
#    grep -n returns all matching lines; we want the "if command -v claude" guard line
#    and the actual "claude plugin tag" invocation line (not the comment referencing it).
CMDV_LINE="$(grep -n "command -v claude" "$BUMP" | head -1 | cut -d: -f1)"
# The actual invocation is "claude plugin tag" on a non-comment line
TAG_LINE="$(grep -n "claude plugin tag" "$BUMP" | grep -v "^[0-9]*:#\|^[0-9]*:.*#.*claude plugin tag" | head -1 | cut -d: -f1)"
# Fallback: use the last match if the above returns empty
if [[ -z "$TAG_LINE" ]]; then
  TAG_LINE="$(grep -n "claude plugin tag" "$BUMP" | tail -1 | cut -d: -f1)"
fi
if [[ -n "$CMDV_LINE" && -n "$TAG_LINE" && "$CMDV_LINE" -lt "$TAG_LINE" ]]; then
  pass "bump.sh: 'command -v claude' guard appears before 'claude plugin tag' invocation"
else
  fail "bump.sh: 'command -v claude' guard appears before 'claude plugin tag' invocation" \
    "command -v on line $CMDV_LINE, claude plugin tag invocation on line $TAG_LINE"
fi

# 5. rnd-bump skill mentions auto-tag behavior
assert_file_contains "rnd-bump skill: mentions auto-tag behavior" "$SKILL" "[Aa]uto"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
