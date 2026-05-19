#!/usr/bin/env bash
# Tests: agent files have correct effort frontmatter,
# plus explicit (model, effort) checks for adaptive-agent baselines.
# Valid effort tokens: low | medium | high | xhigh

set -euo pipefail

AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agents"

pass=0
fail=0

_frontmatter() {
  awk '/^---$/{count++; if(count==2) exit} count==1{print}' "$1"
}

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

  local frontmatter
  frontmatter="$(_frontmatter "$agent_file")"

  # 2. Must have effort: field in frontmatter (between first two --- lines)
  if ! echo "$frontmatter" | grep -qE "^effort:"; then
    echo "FAIL  $agent_name: no 'effort:' field in frontmatter"
    (( fail++ )) || true
    return
  fi

  # 3. Effort value must be a recognised token: low|medium|high|xhigh
  local actual_effort
  actual_effort="$(echo "$frontmatter" | grep -E "^effort:" | awk '{print $2}')"

  if ! echo "$actual_effort" | grep -qE "^(low|medium|high|xhigh)$"; then
    echo "FAIL  $agent_name: effort='$actual_effort' is not a valid token (low|medium|high|xhigh)"
    (( fail++ )) || true
    return
  fi

  # 4. Effort value must match expected
  if [[ "$actual_effort" != "$expected_effort" ]]; then
    echo "FAIL  $agent_name: effort='$actual_effort', expected='$expected_effort'"
    (( fail++ )) || true
    return
  fi

  # 5. effort: must appear immediately after model: (consecutive lines)
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

assert_model_effort() {
  local agent_file="$1"
  local expected_model="$2"
  local expected_effort="$3"
  local agent_name
  agent_name="$(basename "$agent_file")"

  if [[ ! -f "$agent_file" ]]; then
    echo "FAIL  $agent_name (model+effort): file not found"
    (( fail++ )) || true
    return
  fi

  local frontmatter
  frontmatter="$(_frontmatter "$agent_file")"

  local actual_model actual_effort
  actual_model="$(echo "$frontmatter" | grep -E "^model:" | awk '{print $2}')"
  actual_effort="$(echo "$frontmatter" | grep -E "^effort:" | awk '{print $2}')"

  if [[ "$actual_model" == "$expected_model" && "$actual_effort" == "$expected_effort" ]]; then
    echo "PASS  $agent_name: model=$actual_model effort=$actual_effort"
    (( pass++ )) || true
  else
    echo "FAIL  $agent_name: model='$actual_model' effort='$actual_effort', expected model='$expected_model' effort='$expected_effort'"
    (( fail++ )) || true
  fi
}

# --- Effort-only checks ------------------------------------------------------

# opus reasoning agents: planner/verifier use high effort.
assert_effort "$AGENTS_DIR/rnd-planner.md"         "high"
assert_effort "$AGENTS_DIR/rnd-verifier.md"        "high"
assert_effort "$AGENTS_DIR/rnd-debugger.md"        "high"
assert_effort "$AGENTS_DIR/rnd-data-scientist.md"  "medium"

# rnd-builder high; auxiliary agents low.
assert_effort "$AGENTS_DIR/rnd-builder.md"         "high"
assert_effort "$AGENTS_DIR/rnd-integrator.md"      "low"
assert_effort "$AGENTS_DIR/rnd-reality-auditor.md" "low"

# --- Explicit (model, effort) pair checks for adaptive-agent baselines ----------

assert_model_effort "$AGENTS_DIR/rnd-planner.md"           "opus"   "high"
assert_model_effort "$AGENTS_DIR/rnd-verifier.md"          "opus"   "high"
assert_model_effort "$AGENTS_DIR/rnd-polisher.md"          "opus"   "high"
assert_model_effort "$AGENTS_DIR/rnd-builder.md"           "sonnet" "high"

echo ""
echo "Results: $pass passed, $fail failed"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
