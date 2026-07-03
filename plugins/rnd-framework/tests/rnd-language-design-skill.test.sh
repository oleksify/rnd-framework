#!/usr/bin/env bash
# tests/rnd-language-design-skill.test.sh — Regression tests for rnd-language-design skill wiring and content
# Usage: bash tests/rnd-language-design-skill.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

SKILL="${PLUGIN_ROOT}/skills/rnd-language-design/SKILL.md"
DECOMPOSITION_SKILL="${PLUGIN_ROOT}/skills/rnd-decomposition/SKILL.md"
AUDIT_CMD="${PLUGIN_ROOT}/commands/rnd-audit.md"
REVIEW_CMD="${PLUGIN_ROOT}/commands/rnd-review.md"
DEBUG_CMD="${PLUGIN_ROOT}/commands/rnd-debug.md"
BRAINSTORM_CMD="${PLUGIN_ROOT}/commands/rnd-brainstorm.md"

content="$(cat "$SKILL")"
frontmatter_section="$(awk '/^---$/{c++; next} c==1{print}' "$SKILL")"
description_line="$(printf '%s\n' "$frontmatter_section" | grep '^description:')"

decomposition_content="$(cat "$DECOMPOSITION_SKILL")"
audit_content="$(cat "$AUDIT_CMD")"
review_content="$(cat "$REVIEW_CMD")"
debug_content="$(cat "$DEBUG_CMD")"
brainstorm_content="$(cat "$BRAINSTORM_CMD")"

printf '\n--- rnd-language-design skill: frontmatter ---\n'

assert_contains "frontmatter has name: rnd-language-design" \
  "name: rnd-language-design" "$frontmatter_section"

assert_contains "frontmatter has effort: low" \
  "effort: low" "$frontmatter_section"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ "$description_line" == description:\ Use\ when* ]]; then
  printf '  PASS  frontmatter description starts with Use when\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  frontmatter description starts with Use when\n'
  printf '        actual: %s\n' "$description_line"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

printf '\n--- rnd-language-design skill: structure and topics ---\n'

assert_contains "has Overview section" \
  "## Overview" "$content"

assert_contains "has When to Use section" \
  "## When to Use" "$content"

assert_contains "has Core principle wording" \
  "Core principle" "$content"

assert_contains "has The Iron Law section" \
  "## The Iron Law" "$content"

assert_contains "has Process section" \
  "## Process" "$content"

assert_contains "has Common Rationalizations section" \
  "## Common Rationalizations" "$content"

assert_contains "has Verification Checklist section" \
  "## Verification Checklist" "$content"

assert_contains "has Related Skills section" \
  "## Related Skills" "$content"

assert_contains "covers problem framing" \
  "Problem framing" "$content"

assert_contains "covers existing alternatives" \
  "Existing alternatives" "$content"

assert_contains "covers syntax" \
  "Syntax" "$content"

assert_contains "covers grammar" \
  "Grammar" "$content"

assert_contains "covers AST design" \
  "AST design" "$content"

assert_contains "covers semantics" \
  "Semantics" "$content"

assert_contains "covers parser or compiler pipeline" \
  "Parser or compiler pipeline" "$content"

assert_contains "covers renderer or executor" \
  "Renderer or executor" "$content"

assert_contains "covers validator" \
  "Validator" "$content"

assert_contains "covers diagnostics" \
  "Diagnostics" "$content"

assert_contains "covers test design" \
  "Test design" "$content"

assert_contains "covers language evolution" \
  "Language evolution" "$content"

printf '\n--- rnd-language-design skill: empirical specification ---\n'

assert_contains "requires accepted examples" \
  "Accepted examples" "$content"

assert_contains "requires rejected examples" \
  "Rejected examples" "$content"

assert_contains "requires golden AST cases" \
  "golden AST cases" "$content"

assert_contains "requires semantic invariants" \
  "semantic invariants" "$content"

assert_contains "requires diagnostics fixtures" \
  "diagnostics fixtures" "$content"

assert_contains "requires round-trip or rendering checks" \
  "round-trip or rendering checks" "$content"

printf '\n--- rnd-language-design skill: language-agnostic constraints ---\n'

for forbidden in TypeScript JavaScript Python Rust Go Ruby Elixir ANTLR tree-sitter PEG.js Lark Bison Yacc; do
  case "$forbidden" in
    tree-sitter)
      pattern='tree-sitter'
      ;;
    PEG.js)
      pattern='PEG\.js'
      ;;
    *)
      pattern="(^|[^[:alpha:]])${forbidden}([^[:alpha:]]|$)"
      ;;
  esac
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if grep -Eq "$pattern" "$SKILL"; then
    printf '  FAIL  skill avoids language-specific term: %s\n' "$forbidden"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    printf '  PASS  skill avoids language-specific term: %s\n' "$forbidden"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
done

printf '\n--- rnd-language-design skill: pipeline references ---\n'

assert_contains "decomposition references rnd-language-design" \
  "rnd-framework:rnd-language-design" "$decomposition_content"

assert_contains "decomposition uses DSL or small-language trigger" \
  "DSL or small-language" "$decomposition_content"

assert_contains "audit references rnd-language-design" \
  "rnd-framework:rnd-language-design" "$audit_content"

assert_contains "audit uses DSL trigger" \
  "DSL" "$audit_content"

assert_contains "review references rnd-language-design" \
  "rnd-framework:rnd-language-design" "$review_content"

assert_contains "review uses DSL trigger" \
  "DSL" "$review_content"

assert_contains "debug references rnd-language-design" \
  "rnd-framework:rnd-language-design" "$debug_content"

assert_contains "debug uses DSL trigger" \
  "DSL" "$debug_content"

assert_contains "brainstorm references rnd-language-design" \
  "rnd-framework:rnd-language-design" "$brainstorm_content"

assert_contains "brainstorm uses DSL trigger" \
  "DSL" "$brainstorm_content"

report
