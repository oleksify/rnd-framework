#!/usr/bin/env bash
# tests/paraphrase-wiring.test.sh — Content and ordering tests for the
# assertion paraphrase hop wired into Phase 1 post-step of commands/rnd-start.md.
# Usage: bash tests/paraphrase-wiring.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

RND_START="${PLUGIN_ROOT}/commands/rnd-start.md"
PARAPHRASER_AGENT="${PLUGIN_ROOT}/agents/rnd-assertion-paraphraser.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_grep() {
  local desc="$1" pattern="$2" file="$3"
  assert_eq "$desc" "pass" "$(grep -qiE "$pattern" "$file" && printf pass || printf fail)"
}

# Return the first line number matching a pattern (empty string if none).
first_line() {
  grep -n "$1" "$2" | head -1 | cut -d: -f1
}

# ---------------------------------------------------------------------------
# Agent frontmatter checks
# ---------------------------------------------------------------------------

printf '\n--- paraphraser agent: frontmatter ---\n'

assert_grep \
  "agent tools field is Write only" \
  "^tools:[[:space:]]*Write[[:space:]]*$" \
  "$PARAPHRASER_AGENT"

assert_grep \
  "agent model field is haiku" \
  "^model:[[:space:]]*haiku" \
  "$PARAPHRASER_AGENT"

skills_count="$(grep -cE '^skills:' "$PARAPHRASER_AGENT" || true)"
assert_eq "agent has no skills line" "0" "$skills_count"

# ---------------------------------------------------------------------------
# rnd-start.md content presence
# ---------------------------------------------------------------------------

printf '\n--- rnd-start Phase 1 post-step: content presence ---\n'

assert_grep \
  "rnd-start references rnd-assertion-paraphraser" \
  "rnd-assertion-paraphraser" \
  "$RND_START"

assert_grep \
  "rnd-start references paraphrased-assertions.md" \
  "paraphrased-assertions\.md" \
  "$RND_START"

assert_grep \
  "rnd-start references paraphrase-emit.sh" \
  "paraphrase-emit\.sh" \
  "$RND_START"

# ---------------------------------------------------------------------------
# Ordering: paraphraser spawn precedes verifier spawn
# ---------------------------------------------------------------------------

printf '\n--- rnd-start: paraphraser spawn precedes verifier spawn ---\n'

paraphraser_line="$(first_line 'rnd-assertion-paraphraser' "$RND_START")"
verifier_line="$(first_line 'rnd-framework:rnd-verifier' "$RND_START")"

assert_eq \
  "paraphraser reference line found" \
  "pass" \
  "$([ -n "$paraphraser_line" ] && printf pass || printf fail)"

assert_eq \
  "rnd-verifier spawn line found" \
  "pass" \
  "$([ -n "$verifier_line" ] && printf pass || printf fail)"

assert_eq \
  "paraphraser spawn precedes verifier spawn" \
  "pass" \
  "$([ "${paraphraser_line:-0}" -lt "${verifier_line:-0}" ] && printf pass || printf fail)"

# ---------------------------------------------------------------------------
report
