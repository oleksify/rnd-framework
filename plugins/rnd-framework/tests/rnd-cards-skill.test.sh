#!/usr/bin/env bash
# tests/rnd-cards-skill.test.sh — Structural checks for the rnd-cards documentation skill
# and the Card tags field extension in rnd-decomposition.

set -euo pipefail

source "$(dirname "$0")/test-helpers.sh"

SKILLS_DIR="$(cd "$(dirname "$0")/../skills" && pwd)"
CARDS_SKILL="$SKILLS_DIR/rnd-cards/SKILL.md"
DECOMP_SKILL="$SKILLS_DIR/rnd-decomposition/SKILL.md"

# --- VAL-DOC-001: rnd-cards skill exists with correct frontmatter ---

content=""
if [[ -f "$CARDS_SKILL" ]]; then
  content="$(< "$CARDS_SKILL")"
fi

assert_contains "rnd-cards SKILL.md exists" "name: rnd-cards" "$content"
assert_contains "user-invocable: false in rnd-cards" "user-invocable: false" "$content"
assert_contains "effort: low in rnd-cards" "effort: low" "$content"

# Four required sections
assert_contains "authoring section present" "## Card authoring format" "$content"
assert_contains "retrieval section present" "## Retrieval contract" "$content"
assert_contains "injection section present" "## Injection convention" "$content"
assert_contains "tag-choice section present" "## How tags get chosen" "$content"

# Plugin-relative path for card-retrieve.sh
assert_contains "plugin-relative path used" "lib/card-retrieve.sh" "$content"

# Description under 200 chars and starts with action verb — check starts-with
description=""
if [[ -f "$CARDS_SKILL" ]]; then
  description="$(grep '^description:' "$CARDS_SKILL" | head -1 | cut -c14- | tr -d '"')"
fi

desc_len="${#description}"
assert_contains "description starts with action verb" "Use when" "$description"

if [[ $desc_len -lt 200 ]]; then
  assert_eq "description under 200 chars" "under_200" "under_200"
else
  assert_eq "description under 200 chars" "under_200" "over_200"
fi

# --- VAL-DOC-002: Card tags field in rnd-decomposition template ---

decomp_content=""
if [[ -f "$DECOMP_SKILL" ]]; then
  decomp_content="$(< "$DECOMP_SKILL")"
fi

assert_contains "Card tags line present in decomposition template" "Card tags:" "$decomp_content"
assert_contains "optional-in-v1 note present" "optional" "$decomp_content"

report
