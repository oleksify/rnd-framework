#!/usr/bin/env bash
# Tests: All 8 agent files have correct effort frontmatter

set -euo pipefail

AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agents"

pass=0
fail=0

assert_effort() {
  local agent_file="$1"
  local expected_effort="$2"
  local agent_name
  agent_name="$(basename "$agent_file")"

  # 1. File must exist
  if [[ ! -f "$agent_file" ]]; then
    echo "FAIL  $agent_name: file not found"
    (( fail++ )) || true
    return
  fi

  # 2. Must have effort: field in frontmatter (between first two --- lines)
  local frontmatter
  frontmatter="$(awk '/^---$/{count++; if(count==2) exit} count==1{print}' "$agent_file")"

  if ! echo "$frontmatter" | grep -qE "^effort:"; then
    echo "FAIL  $agent_name: no 'effort:' field in frontmatter"
    (( fail++ )) || true
    return
  fi

  # 3. Effort value must match expected
  local actual_effort
  actual_effort="$(echo "$frontmatter" | grep -E "^effort:" | awk '{print $2}')"

  if [[ "$actual_effort" != "$expected_effort" ]]; then
    echo "FAIL  $agent_name: effort='$actual_effort', expected='$expected_effort'"
    (( fail++ )) || true
    return
  fi

  # 4. effort: must appear immediately after model: (consecutive lines)
  local model_line effort_line
  model_line="$(echo "$frontmatter" | grep -n "^model:" | cut -d: -f1)"
  effort_line="$(echo "$frontmatter" | grep -n "^effort:" | cut -d: -f1)"

  if [[ -z "$model_line" || -z "$effort_line" ]]; then
    echo "FAIL  $agent_name: could not find model: or effort: line numbers"
    (( fail++ )) || true
    return
  fi

  local expected_effort_line=$(( model_line + 1 ))
  if [[ "$effort_line" != "$expected_effort_line" ]]; then
    echo "FAIL  $agent_name: effort: is on line $effort_line in frontmatter, expected line $expected_effort_line (immediately after model:)"
    (( fail++ )) || true
    return
  fi

  echo "PASS  $agent_name: effort=$actual_effort (after model: on line $effort_line)"
  (( pass++ )) || true
}

# sonnet reasoning agents: planner/verifier/debugger use high effort (v3.9.0 downgraded from opus/xhigh)
assert_effort "$AGENTS_DIR/rnd-planner.md"         "high"
assert_effort "$AGENTS_DIR/rnd-verifier.md"        "high"
assert_effort "$AGENTS_DIR/rnd-debugger.md"        "high"
assert_effort "$AGENTS_DIR/rnd-data-scientist.md"  "medium"

# sonnet agents → low
assert_effort "$AGENTS_DIR/rnd-builder.md"         "low"
assert_effort "$AGENTS_DIR/rnd-integrator.md"      "low"
assert_effort "$AGENTS_DIR/rnd-proof-gate.md"      "low"
assert_effort "$AGENTS_DIR/rnd-reality-auditor.md" "low"

echo ""
echo "Results: $pass passed, $fail failed"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
