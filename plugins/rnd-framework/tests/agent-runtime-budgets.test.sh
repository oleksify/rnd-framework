#!/usr/bin/env bash
# Tests: All agent files have maxTurns within sane upper bounds

set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

AGENTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/agents"

pass=0
fail=0

assert_max_turns_le() {
  local agent_file="$1"
  local max_allowed="$2"
  local agent_name
  agent_name="$(basename "$agent_file")"

  # 1. File must exist
  if [[ ! -f "$agent_file" ]]; then
    echo "FAIL  $agent_name: file not found"
    (( fail++ )) || true
    return
  fi

  # 2. Must have maxTurns: field in frontmatter (between first two --- lines)
  local frontmatter
  frontmatter="$(awk '/^---$/{count++; if(count==2) exit} count==1{print}' "$agent_file")"

  if ! echo "$frontmatter" | grep -qE "^maxTurns:"; then
    echo "FAIL  $agent_name: no 'maxTurns:' field in frontmatter"
    (( fail++ )) || true
    return
  fi

  # 3. Extract actual value and assert <= max_allowed
  local actual
  actual="$(echo "$frontmatter" | grep -E "^maxTurns:" | awk '{print $2}')"

  if [[ "$actual" -le "$max_allowed" ]]; then
    echo "PASS  $agent_name: maxTurns=$actual (<= $max_allowed)"
    (( pass++ )) || true
  else
    echo "FAIL  $agent_name: maxTurns=$actual exceeds allowed maximum of $max_allowed"
    (( fail++ )) || true
  fi
}

assert_max_turns_le "$AGENTS_DIR/rnd-planner.md"         100
assert_max_turns_le "$AGENTS_DIR/rnd-verifier.md"        100
assert_max_turns_le "$AGENTS_DIR/rnd-builder.md"         200
assert_max_turns_le "$AGENTS_DIR/rnd-cleanup.md"         150
assert_max_turns_le "$AGENTS_DIR/rnd-integrator.md"      150
assert_max_turns_le "$AGENTS_DIR/rnd-reality-auditor.md" 100
assert_max_turns_le "$AGENTS_DIR/rnd-debugger.md"        200
assert_max_turns_le "$AGENTS_DIR/rnd-data-scientist.md"  150

echo ""
echo "Results: $pass passed, $fail failed"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
