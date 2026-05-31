#!/usr/bin/env bash
# Tests for agents/rnd-replan-differ.md — static checks via awk/grep + validate.sh

set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_FILE="$PLUGIN_ROOT/agents/rnd-replan-differ.md"

pass=0
fail=0

_frontmatter() {
  awk '/^---$/{count++; if(count==2) exit} count==1{print}' "$1"
}

_fm_val() {
  local file="$1" key="$2"
  awk -v key="$key" '
    /^---$/ { fm++; next }
    fm==1 && $0 ~ "^"key":" {
      sub("^"key":[ ]*", "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
    fm>=2 { exit }
  ' "$file"
}

assert_eq() {
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS  $label"
    (( pass++ )) || true
  else
    echo "FAIL  $label: got '$actual', expected '$expected'"
    (( fail++ )) || true
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "PASS  $label"
    (( pass++ )) || true
  else
    echo "FAIL  $label: '$needle' not found"
    (( fail++ )) || true
  fi
}

# File exists
if [[ -f "$AGENT_FILE" ]]; then
  echo "PASS  agent file exists"
  (( pass++ )) || true
else
  echo "FAIL  agent file not found: $AGENT_FILE"
  (( fail++ )) || true
  echo ""
  echo "Results: $pass passed, $fail failed"
  exit 1
fi

# --- Frontmatter key/value checks ---

assert_eq "name=rnd-replan-differ" "$(_fm_val "$AGENT_FILE" "name")" "rnd-replan-differ"
assert_eq "model=haiku"            "$(_fm_val "$AGENT_FILE" "model")" "haiku"
assert_eq "effort=low"             "$(_fm_val "$AGENT_FILE" "effort")" "low"

# tools must contain Read and Write
TOOLS_LINE="$(_fm_val "$AGENT_FILE" "tools")"
assert_contains "tools contains Read"  "$TOOLS_LINE" "Read"
assert_contains "tools contains Write" "$TOOLS_LINE" "Write"

# tools must be non-empty (not [])
if [[ "$TOOLS_LINE" == "[]" ]]; then
  echo "FAIL  tools must be non-empty"
  (( fail++ )) || true
else
  echo "PASS  tools is non-empty"
  (( pass++ )) || true
fi

# No skills key in frontmatter
FM="$(_frontmatter "$AGENT_FILE")"
if echo "$FM" | grep -qE "^skills:"; then
  echo "FAIL  frontmatter must not contain 'skills:' key"
  (( fail++ )) || true
else
  echo "PASS  no skills key in frontmatter"
  (( pass++ )) || true
fi

# --- Body content checks ---

BODY_COUNT="$(grep -c '^## Task delta\|^## Assertion delta\|^## Summary' "$AGENT_FILE" || true)"
if [[ "$BODY_COUNT" -eq 3 ]]; then
  echo "PASS  body contains all three required headings"
  (( pass++ )) || true
else
  echo "FAIL  body heading count: got $BODY_COUNT, expected 3"
  (( fail++ )) || true
fi

REPLAN_COUNT="$(grep -c 'replan-diff.md' "$AGENT_FILE" || true)"
if [[ "$REPLAN_COUNT" -ge 1 ]]; then
  echo "PASS  body references replan-diff.md ($REPLAN_COUNT occurrence(s))"
  (( pass++ )) || true
else
  echo "FAIL  body does not reference replan-diff.md"
  (( fail++ )) || true
fi

# --- validate.sh ---

if bash "$PLUGIN_ROOT/lib/validate.sh" --quiet > /dev/null 2>&1; then
  echo "PASS  validate.sh exits 0"
  (( pass++ )) || true
else
  echo "FAIL  validate.sh returned non-zero"
  (( fail++ )) || true
fi

echo ""
echo "Results: $pass passed, $fail failed"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
