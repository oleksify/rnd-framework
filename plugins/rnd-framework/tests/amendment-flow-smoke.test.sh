#!/usr/bin/env bash
# tests/amendment-flow-smoke.test.sh — Smoke test for the AMEND_REQUIRED file-level contract.
# Simulates plan.md mutation and amendment log creation WITHOUT spawning Claude Code agents.
# Tests: synthetic plan.md mutation (old criterion → new criterion) + briefs/T1-amendments.md creation.
# Note: Mutation here is a full-file overwrite, not an Edit-tool surgical patch as the
#       orchestrator performs in production. This test verifies the file-level invariant
#       (old text absent, new text present, log created) — not the Edit mechanism itself.
# Usage: bash tests/amendment-flow-smoke.test.sh
# Exits 0 if all assertions pass, 1 if any fail.

set -euo pipefail

PASS=0
FAIL=0

pass() {
  local name="$1"
  printf 'PASS  %s\n' "$name"
  PASS=$((PASS + 1))
}

fail() {
  local name="$1"
  local detail="$2"
  printf 'FAIL  %s — %s\n' "$name" "$detail"
  FAIL=$((FAIL + 1))
}

assert_contains() {
  local name="$1"
  local file="$2"
  local needle="$3"

  if grep -qF -- "$needle" "$file"; then
    pass "$name"
  else
    fail "$name" "expected '$needle' in $file"
  fi
}

assert_not_contains() {
  local name="$1"
  local file="$2"
  local needle="$3"

  if grep -qF -- "$needle" "$file"; then
    fail "$name" "expected '$needle' to be absent in $file"
  else
    pass "$name"
  fi
}

assert_file_exists() {
  local name="$1"
  local file="$2"

  if [[ -f "$file" ]]; then
    pass "$name"
  else
    fail "$name" "expected file to exist: $file"
  fi
}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

printf '\n--- Setup: temp dir + synthetic plan.md ---\n'

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PLAN_FILE="$TMP_DIR/plan.md"
BRIEFS_DIR="$TMP_DIR/briefs"
AMENDMENT_LOG="$BRIEFS_DIR/T1-amendments.md"

OLD_CRITERION="- [ ] The system returns HTTP 200 for valid requests only"
NEW_CRITERION="- [ ] The system returns HTTP 200 for valid requests with non-empty body"

SYNTHETIC_PLAN="# Plan: Synthetic Pipeline Test

## Task Tree

### T1: Example Task

\`\`\`
Task ID: T1
Intent: Validate HTTP endpoint behavior.
Success criteria:
  Correctness:
  $OLD_CRITERION
\`\`\`
"

printf '%s\n' "$SYNTHETIC_PLAN" > "$PLAN_FILE"
mkdir -p "$BRIEFS_DIR"

assert_contains "plan.md written with old criterion" "$PLAN_FILE" "$OLD_CRITERION"

# ---------------------------------------------------------------------------
# Mutation simulation: old criterion → new criterion
# ---------------------------------------------------------------------------

printf '\n--- Mutation simulation: replace old criterion with new ---\n'

ARBITER_OUTPUT="AMEND
cited_defect: The criterion does not verify response body is non-empty, which is the root cause of the pre-registration defect flagged by the Verifier.
field_patches:
  success_criteria.correctness[0]: $NEW_CRITERION
recommendation: AMEND"

# Simulate plan.md mutation: write updated content with new criterion replacing old
UPDATED_PLAN="# Plan: Synthetic Pipeline Test

## Task Tree

### T1: Example Task

\`\`\`
Task ID: T1
Intent: Validate HTTP endpoint behavior.
Success criteria:
  Correctness:
  $NEW_CRITERION
\`\`\`
"

printf '%s\n' "$UPDATED_PLAN" > "$PLAN_FILE"

assert_not_contains "old criterion absent after mutation" "$PLAN_FILE" "$OLD_CRITERION"
assert_contains "new criterion present after mutation" "$PLAN_FILE" "$NEW_CRITERION"

# ---------------------------------------------------------------------------
# Amendment log creation: append required fields to briefs/T1-amendments.md
# ---------------------------------------------------------------------------

printf '\n--- Amendment log creation and assertion ---\n'

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
CITED_DEFECT="The criterion does not verify response body is non-empty"

AMENDMENT_ENTRY="## Amendment: T1

- timestamp: $TIMESTAMP
- cited-defect: $CITED_DEFECT
- arbiter-recommendation: AMEND
- arbiter-output: |
  $ARBITER_OUTPUT
- user-decision: approved
- old-criterion: $OLD_CRITERION
- new-criterion: $NEW_CRITERION
"

printf '%s\n' "$AMENDMENT_ENTRY" >> "$AMENDMENT_LOG"

assert_file_exists "amendment log file exists" "$AMENDMENT_LOG"
assert_contains "amendment log has timestamp" "$AMENDMENT_LOG" "timestamp:"
assert_contains "amendment log has cited-defect" "$AMENDMENT_LOG" "cited-defect:"
assert_contains "amendment log has user-decision: approved" "$AMENDMENT_LOG" "user-decision: approved"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
