#!/usr/bin/env bash
# Tests for the multi-judge verdict-based escalation gate documentation.
# Verifies that SKILL.md and rnd-start.md contain the required protocol text.
# Usage: bash tests/multi-judge-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MULTI_JUDGE_SKILL="$PLUGIN_DIR/skills/rnd-multi-judge/SKILL.md"
CALIBRATION_SKILL="$PLUGIN_DIR/skills/rnd-calibration/SKILL.md"
RND_START="$PLUGIN_DIR/commands/rnd-start.md"
CLAUDE_MD="$PLUGIN_DIR/../../CLAUDE.md"

PASS=0
FAIL=0

pass() {
  printf 'PASS  %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf 'FAIL  %s — %s\n' "$1" "$2"
  FAIL=$((FAIL + 1))
}

assert_grep() {
  local name="$1"
  local pattern="$2"
  local file="$3"

  if grep -qE "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name" "pattern '$pattern' not found in $file"
  fi
}

assert_no_grep() {
  local name="$1"
  local pattern="$2"
  local file="$3"

  if ! grep -qE "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name" "pattern '$pattern' unexpectedly found in $file"
  fi
}

# ---------------------------------------------------------------------------
# VAL-MJG-001: first-pass single-verifier step present
# ---------------------------------------------------------------------------

printf '\n--- VAL-MJG-001: first-pass step ---\n'

assert_grep \
  "first-pass step present in multi-judge skill" \
  "first.pass|first pass" \
  "$MULTI_JUDGE_SKILL"

# ---------------------------------------------------------------------------
# VAL-MJG-002: PASS_QUALITY_NEEDS_ITERATION named as escalation trigger
# ---------------------------------------------------------------------------

printf '\n--- VAL-MJG-002: PASS_QUALITY_NEEDS_ITERATION as escalation trigger ---\n'

# Both PASS_QUALITY_NEEDS_ITERATION and "Escalate" must appear on the same line
# (i.e., the escalation decision bullet explicitly enumerates the trigger).
if grep -qE "PASS_QUALITY_NEEDS_ITERATION.*[Ee]scalat|[Ee]scalat.*PASS_QUALITY_NEEDS_ITERATION" "$MULTI_JUDGE_SKILL"; then
  pass "PASS_QUALITY_NEEDS_ITERATION co-located with escalation trigger on same line"
else
  fail "PASS_QUALITY_NEEDS_ITERATION co-located with escalation trigger on same line" \
    "no line found where both PASS_QUALITY_NEEDS_ITERATION and 'escalat' appear together"
fi

# ---------------------------------------------------------------------------
# VAL-MJG-003: RND_MULTI_JUDGE_ALWAYS=1 documented in multi-judge skill
# ---------------------------------------------------------------------------

printf '\n--- VAL-MJG-003: RND_MULTI_JUDGE_ALWAYS flag ---\n'

assert_grep \
  "RND_MULTI_JUDGE_ALWAYS documented in multi-judge skill" \
  "RND_MULTI_JUDGE_ALWAYS" \
  "$MULTI_JUDGE_SKILL"

# Flag description must mention restoring pre-change/exact behavior
assert_grep \
  "RND_MULTI_JUDGE_ALWAYS mentions exact pre-change behavior" \
  "exact pre-change behavior|restores exact" \
  "$MULTI_JUDGE_SKILL"

# ---------------------------------------------------------------------------
# VAL-MJG-004: rnd-start Phase 3 references escalation gate and flag
# ---------------------------------------------------------------------------

printf '\n--- VAL-MJG-004: rnd-start Phase 3 references ---\n'

assert_grep \
  "rnd-start references RND_MULTI_JUDGE_ALWAYS or escalation" \
  "RND_MULTI_JUDGE_ALWAYS|escalat|first.pass|first pass" \
  "$RND_START"

# ---------------------------------------------------------------------------
# VAL-MJG-005: all pre-existing H2 headings still present
# ---------------------------------------------------------------------------

printf '\n--- VAL-MJG-005: pre-existing H2 headings intact ---\n'

for heading in "Protocol" "When to Use" "Wave-Batched Multi-Judge Protocol" "Information Barrier Rules" "Related Skills"; do
  assert_grep \
    "heading '## $heading' still present" \
    "^## $heading" \
    "$MULTI_JUDGE_SKILL"
done

# ---------------------------------------------------------------------------
# VAL-CAL-001: escalationGate field in rnd-calibration skill
# ---------------------------------------------------------------------------

printf '\n--- VAL-CAL-001: escalationGate in calibration skill ---\n'

assert_grep \
  "escalationGate field in calibration skill" \
  "escalationGate" \
  "$CALIBRATION_SKILL"

# ---------------------------------------------------------------------------
# VAL-CAL-002: escalation rate stat in calibration stats-injection section
# ---------------------------------------------------------------------------

printf '\n--- VAL-CAL-002: escalation rate stat ---\n'

assert_grep \
  "escalation rate stat present in calibration skill" \
  "escalation rate|first.pass.*overtur|overtur.*first.pass" \
  "$CALIBRATION_SKILL"

# ---------------------------------------------------------------------------
# VAL-CAL-003: escalationGate write instruction in rnd-start
# ---------------------------------------------------------------------------

printf '\n--- VAL-CAL-003: escalationGate in rnd-start ---\n'

assert_grep \
  "escalationGate write instruction in rnd-start" \
  "escalationGate" \
  "$RND_START"

# ---------------------------------------------------------------------------
# VAL-CAL-004: graceful no-op for missing calibration.jsonl
# ---------------------------------------------------------------------------

printf '\n--- VAL-CAL-004: graceful no-op for missing calibration.jsonl ---\n'

assert_grep \
  "graceful no-op wording near escalation write instruction" \
  "silently|graceful|no.op" \
  "$RND_START"

# ---------------------------------------------------------------------------
# VAL-DOC-001: CLAUDE.md rnd-verifier row updated
# ---------------------------------------------------------------------------

printf '\n--- VAL-DOC-001: CLAUDE.md rnd-verifier row ---\n'

assert_grep \
  "RND_MULTI_JUDGE_ALWAYS in CLAUDE.md" \
  "RND_MULTI_JUDGE_ALWAYS" \
  "$CLAUDE_MD"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
