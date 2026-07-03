#!/usr/bin/env bash
# tests/rnd-audit-command.test.sh — Contract tests for rnd-audit coverage/report obligations
# plus the analogous rnd-review and rnd-debug hardening contracts.
# Usage: bash tests/rnd-audit-command.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

AUDIT_CMD="${PLUGIN_ROOT}/commands/rnd-audit.md"
REVIEW_CMD="${PLUGIN_ROOT}/commands/rnd-review.md"
DEBUG_CMD="${PLUGIN_ROOT}/commands/rnd-debug.md"

content="$(cat "$AUDIT_CMD")"
review_content="$(cat "$REVIEW_CMD")"
debug_content="$(cat "$DEBUG_CMD")"

printf '\n--- rnd-audit command: audit coverage ledger ---\n'

assert_contains "requires audit coverage ledger heading" \
  "## Audit Coverage Ledger" "$content"

assert_contains "ledger requires evidence-bearing entries" \
  "evidence-bearing entries for every tracked file group, including skipped groups" "$content"

assert_contains "ledger records tracked file groups" \
  "the tracked file groups examined, including tracked paths or patterns" "$content"

assert_contains "ledger records review categories" \
  "the review categories covered" "$content"

assert_contains "ledger records audit-specific subchecks" \
  "the audit-specific subchecks run" "$content"

assert_contains "ledger records commands or evidence" \
  "commands or evidence used" "$content"

assert_contains "ledger records skipped groups and reasons" \
  "whether the group was examined or skipped, and the reason when skipped" "$content"

assert_contains "ledger records unavailable checks and reasons" \
  "unavailable checks, if any, with reasons" "$content"

assert_contains "ledger requires evidence-backed findings or no findings" \
  "resulting findings, or an explicit \"no findings\" note backed by file paths, line references, or equivalent reproducible evidence" "$content"

printf '\n--- rnd-audit command: audit-specific subchecks ---\n'

assert_contains "covers secrets exposure" \
  "secrets exposure or committed credentials" "$content"

assert_contains "covers shell safety" \
  "shell safety" "$content"

assert_contains "covers information barriers" \
  "information barriers and read gates" "$content"

assert_contains "covers artifact contracts" \
  "artifact contracts and report-path expectations" "$content"

assert_contains "covers dependency trust" \
  "dependency trust, supply chain assumptions, and pinning gaps" "$content"

assert_contains "covers frontend technology detection" \
  "frontend technology detection" "$content"

assert_contains "covers accessibility" \
  "accessibility" "$content"

assert_contains "covers code-inferable UI/UX/design quirks" \
  "code-inferable UI/UX/design quirks" "$content"

assert_contains "covers frontend and backend vulnerable dependency checks" \
  "frontend and backend vulnerable dependency checks" "$content"

assert_contains "covers frontend and backend outdated dependency checks" \
  "frontend and backend outdated dependency checks" "$content"

assert_contains "covers runtime, browser, or screenshot evidence boundary" \
  "runtime, browser, or screenshot evidence" "$content"

assert_contains "covers unavailable-check ledger reporting" \
  "Record unavailable checks in the coverage ledger rather than treating them as clean." "$content"

assert_contains "covers stale docs" \
  "stale docs or stale canonical guidance" "$content"

assert_contains "covers test adequacy" \
  "test adequacy for the code under audit" "$content"

printf '\n--- rnd-audit command: positioning and KISS loading ---\n'

assert_contains "positions audit as full-codebase pass" \
  "full-codebase coverage pass, not a diff review" "$content"

assert_contains "points diff reviews to rnd-review" \
  'for diff-oriented review of recent changes' "$content"

assert_contains "delegates taxonomy to rnd-code-review" \
  'keep `rnd-code-review` as the shared source of truth for the seven review categories, severity levels, verdict taxonomy, and report template' "$content"

assert_contains "invokes rnd-kiss-practices" \
  'Invoke `rnd-framework:rnd-kiss-practices` for the detected tech stack' "$content"

assert_contains "loads only relevant KISS files" \
  "Read only the relevant language-specific KISS files" "$content"

assert_contains "rejects irrelevant KISS files" \
  "Do not load irrelevant language files" "$content"

printf '\n--- rnd-audit command: audit-only boundary ---\n'

assert_contains "declares read-only project-tree boundary" \
  "read-only with respect to the tracked project tree" "$content"

assert_contains "forbids tracked project mutation" \
  "Do not modify, create, delete, format, stage, commit, push, tag, or otherwise mutate tracked project files during the audit." "$content"

assert_contains "limits write exception to audit report" \
  'The only permitted write is `$RND_DIR/audit-report.md`' "$content"

assert_contains "does not start fix pipeline from audit" \
  'Do not start the fix pipeline from inside `rnd-audit`.' "$content"

printf '\n--- rnd-audit command: report artifact and surfacing ---\n'

assert_contains "writes audit report artifact" \
  'Save the audit report to `$RND_DIR/audit-report.md`' "$content"

assert_contains "declares report artifact path" \
  'This command produces the report artifact at `$RND_DIR/audit-report.md`' "$content"

assert_contains "requires verbatim surfacing before next-step prompt" \
  "print the file path followed by the file's complete contents verbatim BEFORE any next-step prompt" "$content"

assert_contains "rejects summary-only surfacing" \
  "Summarizing or merely referencing the file" "$content"

printf '\n--- rnd-review command: review-only boundary and coverage ledger ---\n'

assert_contains "review declares read-only boundary" \
  "read-only with respect to the project tree" "$review_content"

assert_contains "review limits write exception to review report" \
  'The only permitted write is `$RND_DIR/review-report.md`' "$review_content"

assert_contains "review does not fix inline" \
  'Do not fix findings inline from inside `rnd-review`.' "$review_content"

assert_contains "review requires coverage ledger heading" \
  "## Review Coverage Ledger" "$review_content"

assert_contains "review ledger covers every changed file" \
  "an evidence-bearing entry for every changed file, including files that were skipped" "$review_content"

assert_contains "review forbids implied coverage" \
  "Do not imply coverage you did not achieve." "$review_content"

assert_contains "review loads language-design guidance when relevant" \
  'invoke `rnd-framework:rnd-language-design` before reviewing those changes' "$review_content"

printf '\n--- rnd-debug command: diagnosis boundary and verdict-flip stop condition ---\n'

assert_contains "debug declares diagnosis-only boundary" \
  "Diagnosis-Only Boundary" "$debug_content"

assert_contains "debug diagnosis is read-only" \
  "Diagnosis is read-only with respect to the project tree" "$debug_content"

assert_contains "debug checks verdict history before re-iterating" \
  'lib/audit-scan.sh" verdict_history T1' "$debug_content"

assert_contains "debug stops on verdict flip" \
  "FLIP_DETECTED" "$debug_content"

assert_contains "debug loads language-design guidance when relevant" \
  'invoke `rnd-framework:rnd-language-design` before analyzing those paths' "$debug_content"

report
