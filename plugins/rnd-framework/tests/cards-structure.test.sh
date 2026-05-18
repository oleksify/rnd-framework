#!/usr/bin/env bash
# tests/cards-structure.test.sh — Structural checks for seed card library files.

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

CARDS_DIR="$(cd "$(dirname "$0")/../cards" && pwd)"

# Expected card paths (VAL-CARDS-001)
EXPECTED_CARDS=(
  "builder/python/CARD-B1.md"
  "builder/python/CARD-B2.md"
  "builder/python/CARD-B3.md"
  "builder/python/CARD-B4.md"
  "builder/python/CARD-B5.md"
  "builder/python/CARD-B6.md"
  "verifier/python/CARD-V1.md"
  "verifier/python/CARD-V2.md"
  "verifier/python/CARD-V3.md"
  "cleanup/python/CARD-D1.md"
  "cleanup/python/CARD-D2.md"
  "cleanup/python/CARD-D3.md"
  "reality-auditor/generic/CARD-R1.md"
  "reality-auditor/generic/CARD-R2.md"
  "reality-auditor/generic/CARD-R3.md"
  "planner/generic/CARD-P1.md"
  "planner/generic/CARD-P2.md"
)

# VAL-CARDS-001: all 17 card files exist at declared paths
for rel_path in "${EXPECTED_CARDS[@]}"; do
  full_path="$CARDS_DIR/$rel_path"
  if [[ -f "$full_path" ]]; then
    assert_eq "file exists: $rel_path" "exists" "exists"
  else
    assert_eq "file exists: $rel_path" "exists" "missing"
  fi
done

# VAL-CARDS-002: each card has all six required frontmatter fields
REQUIRED_FIELDS=(id role language tags applicable_task_types scope)

for rel_path in "${EXPECTED_CARDS[@]}"; do
  full_path="$CARDS_DIR/$rel_path"

  [[ -f "$full_path" ]] || continue

  content="$(< "$full_path")"

  for field in "${REQUIRED_FIELDS[@]}"; do
    assert_contains "frontmatter $field in $rel_path" "${field}:" "$content"
  done
done

# Body sections: each card has a before/good section, an after/worse section, and a why section.
# Builder/verifier/auditor/planner cards use Good/Worse/Why good is better.
# Cleanup (deletion) cards use Before/After/Why after is better.
for rel_path in "${EXPECTED_CARDS[@]}"; do
  full_path="$CARDS_DIR/$rel_path"

  [[ -f "$full_path" ]] || continue

  content="$(< "$full_path")"

  if [[ "$rel_path" == cleanup/* ]]; then
    assert_contains "Before section in $rel_path" "**Before" "$content"
    assert_contains "After section in $rel_path" "**After" "$content"
    assert_contains "Why section in $rel_path" "**Why after is better" "$content"
  else
    assert_contains "Good section in $rel_path" "**Good" "$content"
    assert_contains "Worse section in $rel_path" "**Worse" "$content"
    assert_contains "Why section in $rel_path" "**Why good is better" "$content"
  fi
done

# Tag taxonomy consistency: spot-check specific tags appear consistently
# error-handling appears in B1 and V1
b1="$(< "$CARDS_DIR/builder/python/CARD-B1.md")"
v1="$(< "$CARDS_DIR/verifier/python/CARD-V1.md")"
assert_contains "error-handling tag in B1" "error-handling" "$b1"
assert_contains "error-handling tag in V1" "error-handling" "$v1"

# abstraction tag appears in B2, V2, D3
b2="$(< "$CARDS_DIR/builder/python/CARD-B2.md")"
v2="$(< "$CARDS_DIR/verifier/python/CARD-V2.md")"
d3="$(< "$CARDS_DIR/cleanup/python/CARD-D3.md")"
assert_contains "abstraction tag in B2" "abstraction" "$b2"
assert_contains "abstraction tag in V2" "abstraction" "$v2"
assert_contains "abstraction tag in D3" "abstraction" "$d3"

# Language field correctness: builder/verifier/cleanup cards use python; reality-auditor/planner use generic
for rel_path in builder/python/CARD-B1.md builder/python/CARD-B6.md \
                verifier/python/CARD-V1.md verifier/python/CARD-V3.md \
                cleanup/python/CARD-D1.md cleanup/python/CARD-D3.md; do
  content="$(< "$CARDS_DIR/$rel_path")"
  assert_contains "language: python in $rel_path" "language: python" "$content"
done

for rel_path in reality-auditor/generic/CARD-R1.md reality-auditor/generic/CARD-R3.md \
                planner/generic/CARD-P1.md planner/generic/CARD-P2.md; do
  content="$(< "$CARDS_DIR/$rel_path")"
  assert_contains "language: generic in $rel_path" "language: generic" "$content"
done

# Cleanup cards use refactor-only applicable_task_types
for rel_path in cleanup/python/CARD-D1.md cleanup/python/CARD-D2.md cleanup/python/CARD-D3.md; do
  content="$(< "$CARDS_DIR/$rel_path")"
  assert_contains "refactor in applicable_task_types for $rel_path" "refactor" "$content"
done

report
