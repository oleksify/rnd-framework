#!/usr/bin/env bash
# Tests: Existence Pre-Pass section in rnd-reality-auditing skill and
# rnd-reality-auditor agent prompt.

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$PLUGIN_DIR/skills/rnd-reality-auditing/SKILL.md"
AGENT="$PLUGIN_DIR/agents/rnd-reality-auditor.md"

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# --- Skill: Existence Pre-Pass section present ---

result=""
if grep -q "Existence Pre-Pass" "$SKILL"; then
  result="found"
fi
assert_eq "skill contains Existence Pre-Pass section" "found" "$result"

# --- Skill: four reference categories ---

result=""
if grep -q "imports" "$SKILL" && grep -q "third-party method" "$SKILL" && grep -q "RFC" "$SKILL" && grep -q "env-var" "$SKILL"; then
  result="found"
fi
assert_eq "skill documents all four reference categories" "found" "$result"

# --- Skill: file-execution constraint (prefers file-path execution) ---

result=""
if grep -q "python file\|file-based\|execute.*by path\|file.*path" "$SKILL"; then
  result="found"
fi
assert_eq "skill recommends file-path execution for probes" "found" "$result"

# --- Skill: Report Template includes Existence Pre-Pass section ---

result=""
if grep -q "## Existence Pre-Pass" "$SKILL"; then
  result="found"
fi
assert_eq "Reality Report Template includes ## Existence Pre-Pass section" "found" "$result"

# --- Skill: EXISTS | MISSING | UNCHECKED verdicts in template ---

result=""
if grep -q "EXISTS" "$SKILL" && grep -q "MISSING" "$SKILL" && grep -q "UNCHECKED" "$SKILL"; then
  result="found"
fi
assert_eq "skill documents EXISTS | MISSING | UNCHECKED verdicts" "found" "$result"

# --- Skill: MISSING short-circuits to INVALID_FOUND ---

result=""
if grep -q "INVALID_FOUND" "$SKILL"; then
  result="found"
fi
assert_eq "skill documents MISSING short-circuits to INVALID_FOUND" "found" "$result"

# --- Skill: FALSE_PASS_PROXY calibration emission documented ---

result=""
if grep -q "FALSE_PASS_PROXY" "$SKILL"; then
  result="found"
fi
assert_eq "skill documents FALSE_PASS_PROXY calibration record emission" "found" "$result"

# --- Skill: cross-references rnd-calibration ---

result=""
if grep -q "rnd-calibration" "$SKILL"; then
  result="found"
fi
assert_eq "skill cross-references rnd-framework:rnd-calibration" "found" "$result"

# --- Agent: Step 0 referencing existence pre-pass ---

result=""
if grep -qE "^0\." "$AGENT"; then
  result="found"
fi
assert_eq "agent Process list contains a Step 0 before adversarial experiments" "found" "$result"

# --- Agent: Step 0 before Step 1 (ordering) ---

step0_line=""
step1_line=""
step0_line="$(grep -nE "^0\." "$AGENT" | head -1 | cut -d: -f1 || true)"
step1_line="$(grep -nE "^1\." "$AGENT" | head -1 | cut -d: -f1 || true)"

result=""
if [[ -n "$step0_line" && -n "$step1_line" && "$step0_line" -lt "$step1_line" ]]; then
  result="ordered"
fi
assert_eq "Step 0 appears before Step 1 in agent prompt" "ordered" "$result"

# --- Agent: recommends file-path execution over inline flags ---

result=""
if grep -q "file execution\|execute.*by path\|file.*path\|python file\|file-based" "$AGENT"; then
  result="found"
fi
assert_eq "agent recommends file-path execution for probes" "found" "$result"

# --- Agent: FALSE_PASS_PROXY emission documented ---

result=""
if grep -q "FALSE_PASS_PROXY" "$AGENT"; then
  result="found"
fi
assert_eq "agent documents FALSE_PASS_PROXY emission" "found" "$result"

report
