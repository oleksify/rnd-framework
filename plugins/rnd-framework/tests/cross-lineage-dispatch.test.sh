#!/usr/bin/env bash
# Tests for the HIGH-PII cross-lineage verifier dispatch feature.
# Verifies that rnd-start.md, rnd-orchestration/SKILL.md, and
# rnd-decomposition/SKILL.md contain the required protocol text,
# and that lib/calibration.sh handles HIGH-PII correctly.
# Usage: bash tests/cross-lineage-dispatch.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RND_START="$PLUGIN_DIR/commands/rnd-start.md"
ORCHESTRATION_SKILL="$PLUGIN_DIR/skills/rnd-orchestration/SKILL.md"
DECOMPOSITION_SKILL="$PLUGIN_DIR/skills/rnd-decomposition/SKILL.md"
CALIBRATION="$PLUGIN_DIR/lib/calibration.sh"

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
  local name="$1" pattern="$2" file="$3"

  if grep -qE "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name" "pattern '$pattern' not found in $file"
  fi
}

# ---------------------------------------------------------------------------
# 1. HIGH-PII appears in all three documentation files
# ---------------------------------------------------------------------------

printf '\n--- HIGH-PII presence in documentation files ---\n'

assert_grep \
  "HIGH-PII present in rnd-start.md" \
  "HIGH-PII" \
  "$RND_START"

assert_grep \
  "HIGH-PII present in rnd-orchestration/SKILL.md" \
  "HIGH-PII" \
  "$ORCHESTRATION_SKILL"

assert_grep \
  "HIGH-PII present in rnd-decomposition/SKILL.md" \
  "HIGH-PII" \
  "$DECOMPOSITION_SKILL"

# ---------------------------------------------------------------------------
# 2. cross_lineage_verifier audit event emit is in rnd-start.md
# ---------------------------------------------------------------------------

printf '\n--- cross_lineage_verifier audit event ---\n'

assert_grep \
  "cross_lineage_verifier audit event in rnd-start.md" \
  "cross_lineage_verifier" \
  "$RND_START"

# The audit event must carry task_id, lineage_a, lineage_b, agreed fields
assert_grep \
  "cross_lineage_verifier event has lineage_a field" \
  "lineage_a" \
  "$RND_START"

assert_grep \
  "cross_lineage_verifier event has lineage_b field" \
  "lineage_b" \
  "$RND_START"

assert_grep \
  "cross_lineage_verifier event has agreed field" \
  'agreed' \
  "$RND_START"

# ---------------------------------------------------------------------------
# 3. Two distinct model lineages (sonnet + opus) named in dispatch block
# ---------------------------------------------------------------------------

printf '\n--- Dual model lineage dispatch (sonnet + opus) ---\n'

# Both model values must appear in rnd-start.md
assert_grep \
  "model: sonnet present in rnd-start.md dispatch" \
  'model: "?sonnet"?' \
  "$RND_START"

assert_grep \
  "model: opus present in rnd-start.md dispatch" \
  'model: "?opus"?' \
  "$RND_START"

# The orchestration skill matrix must document dual-spawn for HIGH-PII
assert_grep \
  "dual-spawn documented in orchestration skill matrix" \
  "dual.spawn|sonnet.*opus|opus.*sonnet" \
  "$ORCHESTRATION_SKILL"

# ---------------------------------------------------------------------------
# 4. Unanimous PASS path and tiebreaker routing documented
# ---------------------------------------------------------------------------

printf '\n--- Verdict routing: unanimous PASS and tiebreaker ---\n'

assert_grep \
  "unanimous PASS produces final PASS in rnd-start.md" \
  "[Bb]oth.*PASS|unanimous.*PASS|PASS.*unanimous" \
  "$RND_START"

assert_grep \
  "disagreement routes to tiebreaker in rnd-start.md" \
  "tiebreaker" \
  "$RND_START"

# ---------------------------------------------------------------------------
# 5. Cost trade-off documented for Planners
# ---------------------------------------------------------------------------

printf '\n--- Cost trade-off warning ---\n'

assert_grep \
  "cost note (2x) mentioned in rnd-start.md" \
  '2.*verifier|2×.*[Vv]erifier|[Vv]erifier.*2×' \
  "$RND_START"

assert_grep \
  "cost note mentioned in rnd-decomposition/SKILL.md" \
  '2×|2x' \
  "$DECOMPOSITION_SKILL"

# HIGH-PII sub-tier must be restricted to auth/payment/PII domains
assert_grep \
  "auth/payment/PII scope restriction in rnd-start.md" \
  "[Aa]uth.*[Pp][Ii][Ii]|[Pp][Ii][Ii].*[Aa]uth|portal.to.hell|payment" \
  "$RND_START"

# ---------------------------------------------------------------------------
# 6. calibration.sh promote_tier HIGH-PII exits 0 and prints HIGH-PII
# ---------------------------------------------------------------------------

printf '\n--- calibration.sh promote_tier HIGH-PII ---\n'

promote_out=""
promote_exit=0
promote_out="$(bash "$CALIBRATION" promote_tier HIGH-PII 2>&1)" || promote_exit=$?

if [[ "$promote_exit" -eq 0 ]]; then
  pass "promote_tier HIGH-PII exits 0"
else
  fail "promote_tier HIGH-PII exits 0" "exit code was $promote_exit"
fi

if [[ "$promote_out" == "HIGH-PII" ]]; then
  pass "promote_tier HIGH-PII prints HIGH-PII (terminal tier)"
else
  fail "promote_tier HIGH-PII prints HIGH-PII (terminal tier)" "got: $promote_out"
fi

# Existing tier promotions must still work correctly
low_out="$(bash "$CALIBRATION" promote_tier LOW 2>&1)"
if [[ "$low_out" == "MEDIUM" ]]; then
  pass "promote_tier LOW still returns MEDIUM (no regression)"
else
  fail "promote_tier LOW still returns MEDIUM (no regression)" "got: $low_out"
fi

high_out="$(bash "$CALIBRATION" promote_tier HIGH 2>&1)"
if [[ "$high_out" == "HIGH" ]]; then
  pass "promote_tier HIGH still returns HIGH (no regression)"
else
  fail "promote_tier HIGH still returns HIGH (no regression)" "got: $high_out"
fi

# ---------------------------------------------------------------------------
# 7. Existing HIGH-criticality multi-judge path still referenced
# ---------------------------------------------------------------------------

printf '\n--- Default HIGH-criticality multi-judge path preserved ---\n'

assert_grep \
  "rnd-multi-judge still referenced in rnd-start.md" \
  "rnd-multi-judge" \
  "$RND_START"

assert_grep \
  "multi-judge protocol still in HIGH criticality dispatch" \
  "HIGH.criticality.*multi.judge|multi.judge.*HIGH" \
  "$RND_START"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
