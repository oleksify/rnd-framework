#!/usr/bin/env bash
# Tests for Phase 8 (post-SHIP code review) in commands/rnd-start.md.
# Usage: bash tests/phase8-post-ship-review.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RND_START="${SCRIPT_DIR}/../commands/rnd-start.md"
RND_STATUS="${SCRIPT_DIR}/../commands/rnd-status.md"
RND_RESUME="${SCRIPT_DIR}/../commands/rnd-resume.md"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Phase 8 section exists in rnd-start.md, positioned after Phase 7
# ---------------------------------------------------------------------------
printf '%s\n' '--- phase8: section present after Phase 7 ---'

phase7_line="$(grep -n "^## Phase 7" "$RND_START" | head -1 | cut -d: -f1)"
phase8_line="$(grep -n "^## Phase 8" "$RND_START" | head -1 | cut -d: -f1)"

assert_contains "Phase 8 heading exists" "Phase 8" "$(grep -c "^## Phase 8" "$RND_START" | xargs echo Phase 8 count:)"

if [[ -n "$phase7_line" && -n "$phase8_line" ]]; then
  if [[ "$phase8_line" -gt "$phase7_line" ]]; then
    printf '  PASS  Phase 8 is positioned after Phase 7 (line %s > line %s)\n' "$phase8_line" "$phase7_line"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  Phase 8 is NOT after Phase 7 (Phase 7 at line %s, Phase 8 at line %s)\n' "$phase7_line" "$phase8_line"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
else
  printf '  FAIL  Could not find Phase 7 (line %s) or Phase 8 (line %s) headings\n' "${phase7_line:-MISSING}" "${phase8_line:-MISSING}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
fi

# Phase 8 body references the code-review skill, not a duplicated copy
assert_contains "Phase 8 references rnd-framework:rnd-code-review (not duplicated)" "rnd-framework:rnd-code-review" \
  "$(awk '/^## Phase 8/,0' "$RND_START" | grep "rnd-framework:rnd-code-review" | head -1)"

# Phase 8 mentions the pipeline runs it (not the user)
assert_contains "Phase 8 says run by pipeline, not user" "not the user" \
  "$(awk '/^## Phase 8/,0' "$RND_START" | grep "not the user" | head -1)"

# Phase 8 fires after final wave SHIP (Gate 5)
assert_contains "Phase 8 trigger references Gate 5 SHIP" "Gate 5" \
  "$(awk '/^## Phase 8/,0' "$RND_START" | grep "Gate 5" | head -1)"

# Phase 8 writes to review/ directory
assert_contains "Phase 8 writes post-ship-review.md" "post-ship-review.md" \
  "$(awk '/^## Phase 8/,0' "$RND_START" | grep "post-ship-review.md" | head -1)"

# ---------------------------------------------------------------------------
# Opt-out flag present, mirrors skip-reality-checks, emits audit event on skip
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- phase8: opt-out flag and audit event ---'

phase8_block="$(awk '/^## Phase 8/,0' "$RND_START")"

# Flag is named --skip-post-review (mirrors --skip-reality-checks)
assert_contains "opt-out flag is --skip-post-review" "--skip-post-review" "$phase8_block"

# Flag mirrors --skip-reality-checks (the precedent is named)
assert_contains "opt-out flag mirrors --skip-reality-checks" "--skip-reality-checks" "$phase8_block"

# On skip, emits post-review-skip audit event via audit-event.sh
assert_contains "skip emits post-review-skip event" "post-review-skip" "$phase8_block"

# References lib/audit-event.sh
assert_contains "skip uses lib/audit-event.sh" "audit-event.sh" "$phase8_block"

# ---------------------------------------------------------------------------
# Status and resume commands still classify pipeline as complete after Phase 8
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- phase8: status/resume still classify complete via All waves SHIP ---'

# rnd-resume.md Step 9 uses "All waves SHIP" as the complete condition
assert_contains "rnd-resume Step 9 has All waves SHIP rule" "All waves SHIP" \
  "$(cat "$RND_RESUME")"

# rnd-status.md determines integrated status via integration/wave-*-report.md
assert_contains "rnd-status scans integration reports for SHIP" "integration/wave-" \
  "$(cat "$RND_STATUS")"

# Neither file references a phase-number ceiling (Phase 8 won't violate it)
# Confirm no "Phase [0-9]" ceiling in the status rules section
status_rules="$(awk '/^### Status determination/,/^###/' "$RND_STATUS" | head -30)"
phase_ceiling_count="$(printf '%s' "$status_rules" | grep -c "phase.*[0-9]\|[0-9].*phase" || true)"
assert_eq "status rules have no phase-number ceiling" "0" "$phase_ceiling_count"

# Phase 8 artifacts are NOT in the directories rnd-resume scans
# (builds/, verifications/, integration/) — only review/ and slug-root post-review.jsonl
assert_contains "Phase 8 notes status/resume safety" "Status/resume safety" \
  "$(awk '/^## Phase 8/,0' "$RND_START")"

# ---------------------------------------------------------------------------
# Quality: Phase 8 does not duplicate the seven-category review text
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- phase8: review prose referenced, not duplicated ---'

# Confirm "seven categories" or "seven review categories" appear in Phase 8
assert_contains "Phase 8 mentions seven categories by reference" "seven" \
  "$(awk '/^## Phase 8/,0' "$RND_START")"

# Confirm Phase 8 does NOT contain the literal seven-category enumeration
# (architecture, security, correctness, testing, KISS, style, pipeline-context)
# as a standalone list — it should reference the skill instead.
# We check that the section body delegates via skill invocation.
assert_contains "Phase 8 delegates to rnd-framework:rnd-code-review skill" "rnd-framework:rnd-code-review" \
  "$(awk '/^## Phase 8/,0' "$RND_START" | grep "rnd-framework:rnd-code-review")"

# ---------------------------------------------------------------------------
report
