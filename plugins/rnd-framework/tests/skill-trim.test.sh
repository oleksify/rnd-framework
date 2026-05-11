#!/usr/bin/env bash
# tests/skill-trim.test.sh — Asserts char count targets and heading parity for trimmed skill files.
# Usage: bash tests/skill-trim.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

SKILLS_DIR="${SCRIPT_DIR}/../skills"

MULTI_JUDGE="${SKILLS_DIR}/rnd-multi-judge/SKILL.md"
CODE_REVIEW="${SKILLS_DIR}/code-review/SKILL.md"
DOC_POLISH="${SKILLS_DIR}/rnd-doc-polish/SKILL.md"

# ── char count targets ────────────────────────────────────────────────────────

printf '%s\n' '--- char count targets ---'

multi_judge_chars="$(wc -c < "$MULTI_JUDGE")"
assert_eq "rnd-multi-judge char count ≤ 6325 (VAL-TRIM-001)" "pass" \
  "$([ "$multi_judge_chars" -le 6325 ] && printf pass || printf fail)"

code_review_chars="$(wc -c < "$CODE_REVIEW")"
assert_eq "code-review char count ≤ 2828 (VAL-TRIM-002)" "pass" \
  "$([ "$code_review_chars" -le 2828 ] && printf pass || printf fail)"

doc_polish_chars="$(wc -c < "$DOC_POLISH")"
assert_eq "rnd-doc-polish char count ≤ 2803 (VAL-TRIM-003)" "pass" \
  "$([ "$doc_polish_chars" -le 2803 ] && printf pass || printf fail)"

# ── heading presence: rnd-multi-judge ────────────────────────────────────────

printf '%s\n' '--- rnd-multi-judge headings (VAL-TRIM-004) ---'

has_h2() {
  grep -q "^## $1" "$2"
}

assert_eq "rnd-multi-judge: ## When to Use" "pass" \
  "$(has_h2 "When to Use" "$MULTI_JUDGE" && printf pass || printf fail)"

assert_eq "rnd-multi-judge: ## Wave-Batched Multi-Judge Protocol" "pass" \
  "$(has_h2 "Wave-Batched Multi-Judge Protocol" "$MULTI_JUDGE" && printf pass || printf fail)"

assert_eq "rnd-multi-judge: ## Protocol" "pass" \
  "$(has_h2 "Protocol" "$MULTI_JUDGE" && printf pass || printf fail)"

assert_eq "rnd-multi-judge: ## Information Barrier Rules" "pass" \
  "$(has_h2 "Information Barrier Rules" "$MULTI_JUDGE" && printf pass || printf fail)"

assert_eq "rnd-multi-judge: ## Related Skills" "pass" \
  "$(has_h2 "Related Skills" "$MULTI_JUDGE" && printf pass || printf fail)"

# ── heading presence: code-review ────────────────────────────────────────────

printf '%s\n' '--- code-review headings (VAL-TRIM-005) ---'

assert_eq "code-review: ## Overview" "pass" \
  "$(has_h2 "Overview" "$CODE_REVIEW" && printf pass || printf fail)"

assert_eq "code-review: ## Review Categories" "pass" \
  "$(has_h2 "Review Categories" "$CODE_REVIEW" && printf pass || printf fail)"

assert_eq "code-review: ## Severity Levels" "pass" \
  "$(has_h2 "Severity Levels" "$CODE_REVIEW" && printf pass || printf fail)"

assert_eq "code-review: ## Verdicts" "pass" \
  "$(has_h2 "Verdicts" "$CODE_REVIEW" && printf pass || printf fail)"

assert_eq "code-review: ## Review Report Template" "pass" \
  "$(has_h2 "Review Report Template" "$CODE_REVIEW" && printf pass || printf fail)"

assert_eq "code-review: ## Review Rules" "pass" \
  "$(has_h2 "Review Rules" "$CODE_REVIEW" && printf pass || printf fail)"

assert_eq "code-review: ## Related Skills" "pass" \
  "$(has_h2 "Related Skills" "$CODE_REVIEW" && printf pass || printf fail)"

# ── heading presence: rnd-doc-polish ─────────────────────────────────────────

printf '%s\n' '--- rnd-doc-polish headings (VAL-TRIM-006) ---'

assert_eq "rnd-doc-polish: ## When to Use" "pass" \
  "$(has_h2 "When to Use" "$DOC_POLISH" && printf pass || printf fail)"

assert_eq "rnd-doc-polish: ## Process" "pass" \
  "$(has_h2 "Process" "$DOC_POLISH" && printf pass || printf fail)"

assert_eq "rnd-doc-polish: ## What NOT to Do" "pass" \
  "$(has_h2 "What NOT to Do" "$DOC_POLISH" && printf pass || printf fail)"

has_h3() {
  grep -q "^### $1" "$2"
}

assert_eq "rnd-doc-polish: ### 1. Scope the Changes" "pass" \
  "$(has_h3 "1. Scope the Changes" "$DOC_POLISH" && printf pass || printf fail)"

assert_eq "rnd-doc-polish: ### 2. Check CLAUDE.md" "pass" \
  "$(has_h3 "2. Check CLAUDE.md" "$DOC_POLISH" && printf pass || printf fail)"

assert_eq "rnd-doc-polish: ### 3. Check README.md" "pass" \
  "$(has_h3 "3. Check README.md" "$DOC_POLISH" && printf pass || printf fail)"

assert_eq "rnd-doc-polish: ### 4. Check Project-Specific Docs" "pass" \
  "$(has_h3 "4. Check Project-Specific Docs" "$DOC_POLISH" && printf pass || printf fail)"

assert_eq "rnd-doc-polish: ### 5. Check Stale Inline Comments" "pass" \
  "$(has_h3 "5. Check Stale Inline Comments" "$DOC_POLISH" && printf pass || printf fail)"

assert_eq "rnd-doc-polish: ### 6. Report" "pass" \
  "$(has_h3 "6. Report" "$DOC_POLISH" && printf pass || printf fail)"

# ── report ────────────────────────────────────────────────────────────────────

report
