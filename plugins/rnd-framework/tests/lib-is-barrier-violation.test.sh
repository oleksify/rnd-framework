#!/usr/bin/env bash
# tests/lib-is-barrier-violation.test.sh — Tests for is_barrier_violation in hooks/lib.sh.
# Usage: bash tests/lib-is-barrier-violation.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

LIB="${SCRIPT_DIR}/../hooks/lib.sh"
# shellcheck source=../hooks/lib.sh
source "$LIB"

printf '%s\n' '--- is_barrier_violation ---'

TEXT="path/to/self-assessment.md"

# Lean theorem: proofGate_cannot_access_self_assessment
# proof-gate agent must be blocked from self-assessment paths
if is_barrier_violation "$TEXT" "rnd-proof-gate"; then
  assert_eq "proof-gate blocked from self-assessment (proofGate_cannot_access_self_assessment)" "0" "0"
else
  assert_eq "proof-gate blocked from self-assessment (proofGate_cannot_access_self_assessment)" "0" "1"
fi

# Regression: verifier must still be blocked
if is_barrier_violation "$TEXT" "rnd-verifier"; then
  assert_eq "verifier blocked from self-assessment (regression)" "0" "0"
else
  assert_eq "verifier blocked from self-assessment (regression)" "0" "1"
fi

# Builder must NOT be blocked
if is_barrier_violation "$TEXT" "rnd-builder"; then
  assert_eq "builder NOT blocked from self-assessment" "1" "0"
else
  assert_eq "builder NOT blocked from self-assessment" "1" "1"
fi

# Regression: empty agent_type must be blocked
if is_barrier_violation "$TEXT" ""; then
  assert_eq "empty agent_type blocked from self-assessment (regression)" "0" "0"
else
  assert_eq "empty agent_type blocked from self-assessment (regression)" "0" "1"
fi

# polisher agent must be blocked from self-assessment paths
if is_barrier_violation "path/to/self-assessment.md" "rnd-polisher"; then
  assert_eq "polisher blocked from self-assessment" "0" "0"
else
  assert_eq "polisher blocked from self-assessment" "0" "1"
fi

# polisher agent must be blocked from /briefs/ paths under .rnd/
if is_barrier_violation "/Users/x/.claude/.rnd/sessions/20260101-120000-abcd/briefs/decisions.md" "rnd-polisher"; then
  assert_eq "polisher blocked from .rnd/.../briefs/" "0" "0"
else
  assert_eq "polisher blocked from .rnd/.../briefs/" "0" "1"
fi

# polisher agent must be blocked from /cleanup/ paths under .rnd/
if is_barrier_violation "/Users/x/.claude/.rnd/sessions/20260101-120000-abcd/cleanup/T1-cleanup-report.md" "rnd-polisher"; then
  assert_eq "polisher blocked from .rnd/.../cleanup/" "0" "0"
else
  assert_eq "polisher blocked from .rnd/.../cleanup/" "0" "1"
fi

# polisher agent must NOT be blocked from benign paths
if is_barrier_violation "/tmp/file.md" "rnd-polisher"; then
  assert_eq "polisher NOT blocked from benign path" "1" "0"
else
  assert_eq "polisher NOT blocked from benign path" "1" "1"
fi

# Corpus path collision: cards/cleanup/... is the flash-card priming corpus,
# NOT an artifact-tree cleanup report. Must NOT be barrier-violating.
CORPUS_CLEANUP="/Users/x/.claude/plugins/cache/oleksify-plugins/rnd-framework/3.22.2/cards/cleanup/python/CARD-D1.md"
if is_barrier_violation "$CORPUS_CLEANUP" ""; then
  assert_eq "cards/cleanup/ corpus path NOT a barrier violation (empty agent)" "1" "0"
else
  assert_eq "cards/cleanup/ corpus path NOT a barrier violation (empty agent)" "1" "1"
fi

if is_barrier_violation "$CORPUS_CLEANUP" "rnd-verifier"; then
  assert_eq "cards/cleanup/ corpus path NOT a barrier violation (verifier)" "1" "0"
else
  assert_eq "cards/cleanup/ corpus path NOT a barrier violation (verifier)" "1" "1"
fi

# Realistic .rnd/ artifact tree cleanup-report IS a barrier violation.
RND_CLEANUP="/Users/x/.claude/.rnd/claude-abc/branches/main/sessions/20260101-120000-abcd/cleanup/T1-cleanup-report.md"
if is_barrier_violation "$RND_CLEANUP" ""; then
  assert_eq ".rnd/.../cleanup/ IS a barrier violation (empty agent)" "0" "0"
else
  assert_eq ".rnd/.../cleanup/ IS a barrier violation (empty agent)" "0" "1"
fi

if is_barrier_violation "$RND_CLEANUP" "rnd-verifier"; then
  assert_eq ".rnd/.../cleanup/ IS a barrier violation (verifier)" "0" "0"
else
  assert_eq ".rnd/.../cleanup/ IS a barrier violation (verifier)" "0" "1"
fi

# Realistic .rnd/ artifact tree briefs path IS a barrier violation.
RND_BRIEFS="/Users/x/.claude/.rnd/claude-abc/branches/main/sessions/20260101-120000-abcd/briefs/T1-briefs.md"
if is_barrier_violation "$RND_BRIEFS" ""; then
  assert_eq ".rnd/.../briefs/ IS a barrier violation (empty agent)" "0" "0"
else
  assert_eq ".rnd/.../briefs/ IS a barrier violation (empty agent)" "0" "1"
fi

# Self-assessment regression: still blocked regardless of .rnd/ context.
if is_barrier_violation "path/to/self-assessment.md" ""; then
  assert_eq "self-assessment still blocked without .rnd/ context (regression)" "0" "0"
else
  assert_eq "self-assessment still blocked without .rnd/ context (regression)" "0" "1"
fi

report
