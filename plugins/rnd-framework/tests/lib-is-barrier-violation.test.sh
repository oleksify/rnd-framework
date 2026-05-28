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

# verifier must be blocked from self-assessment paths
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

# Orchestrator (empty agent_type) must NOT be blocked — it relays self-assessment
# content to the user per the orchestration protocol.
if is_barrier_violation "$TEXT" ""; then
  assert_eq "empty agent_type NOT blocked from self-assessment (orchestrator)" "1" "0"
else
  assert_eq "empty agent_type NOT blocked from self-assessment (orchestrator)" "1" "1"
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

# Realistic .rnd/ artifact tree cleanup-report IS a barrier violation.
RND_CLEANUP="/Users/x/.claude/.rnd/claude-abc/branches/main/sessions/20260101-120000-abcd/cleanup/T1-cleanup-report.md"
if is_barrier_violation "$RND_CLEANUP" ""; then
  assert_eq ".rnd/.../cleanup/ NOT a barrier violation for empty agent (orchestrator)" "1" "0"
else
  assert_eq ".rnd/.../cleanup/ NOT a barrier violation for empty agent (orchestrator)" "1" "1"
fi

if is_barrier_violation "$RND_CLEANUP" "rnd-verifier"; then
  assert_eq ".rnd/.../cleanup/ IS a barrier violation (verifier)" "0" "0"
else
  assert_eq ".rnd/.../cleanup/ IS a barrier violation (verifier)" "0" "1"
fi

# Realistic .rnd/ artifact tree briefs path IS a barrier violation.
RND_BRIEFS="/Users/x/.claude/.rnd/claude-abc/branches/main/sessions/20260101-120000-abcd/briefs/T1-briefs.md"
if is_barrier_violation "$RND_BRIEFS" ""; then
  assert_eq ".rnd/.../briefs/ NOT a barrier violation for empty agent (orchestrator)" "1" "0"
else
  assert_eq ".rnd/.../briefs/ NOT a barrier violation for empty agent (orchestrator)" "1" "1"
fi

# Self-assessment: orchestrator (empty agent_type) is allowed — it relays these to the user.
if is_barrier_violation "path/to/self-assessment.md" ""; then
  assert_eq "self-assessment NOT a barrier violation for empty agent (orchestrator)" "1" "0"
else
  assert_eq "self-assessment NOT a barrier violation for empty agent (orchestrator)" "1" "1"
fi

# --- self-assessment match anchored to the .md artifact suffix ---
# The real Builder artifact builds/T<id>-self-assessment.md is STILL blocked (absolute).
RND_SELFASSESS="/Users/x/.claude/.rnd/claude-abc/branches/main/sessions/20260101-120000-abcd/builds/M2.T02.foo-self-assessment.md"
if is_barrier_violation "$RND_SELFASSESS" "rnd-verifier"; then
  assert_eq "verifier blocked from builds/<task>-self-assessment.md artifact" "0" "0"
else
  assert_eq "verifier blocked from builds/<task>-self-assessment.md artifact" "0" "1"
fi

# Still blocked via a RELATIVE reference to the artifact (preserves prior protection).
if is_barrier_violation "builds/T01-self-assessment.md" "rnd-verifier"; then
  assert_eq "verifier blocked from RELATIVE self-assessment.md artifact" "0" "0"
else
  assert_eq "verifier blocked from RELATIVE self-assessment.md artifact" "0" "1"
fi

# The property-runner output (builds/T<id>-self-assessment-properties.txt) is STILL blocked.
if is_barrier_violation "/Users/x/.claude/.rnd/claude-abc/branches/main/sessions/20260101-120000-abcd/builds/T99-self-assessment-properties.txt" "rnd-verifier"; then
  assert_eq "verifier blocked from self-assessment-properties.txt (property output)" "0" "0"
else
  assert_eq "verifier blocked from self-assessment-properties.txt (property output)" "0" "1"
fi

# The legitimately-named producer SOURCE file is NOT blocked (no "self-assessment.md" substring).
if is_barrier_violation "/Users/x/plugins/rnd-framework/hooks/self-assessment-producer.sh" "rnd-verifier"; then
  assert_eq "verifier NOT blocked from hooks/self-assessment-producer.sh" "1" "0"
else
  assert_eq "verifier NOT blocked from hooks/self-assessment-producer.sh" "1" "1"
fi

# The producer TEST file is NOT blocked for the polisher.
if is_barrier_violation "plugins/rnd-framework/tests/self-assessment-producer.test.sh" "rnd-polisher"; then
  assert_eq "polisher NOT blocked from tests/self-assessment-producer.test.sh" "1" "0"
else
  assert_eq "polisher NOT blocked from tests/self-assessment-producer.test.sh" "1" "1"
fi

# A Bash command that RUNS the producer test is NOT blocked (lacks "self-assessment.md").
if is_barrier_violation "bash tests/self-assessment-producer.test.sh" "rnd-verifier"; then
  assert_eq "verifier NOT blocked from running the producer test" "1" "0"
else
  assert_eq "verifier NOT blocked from running the producer test" "1" "1"
fi

report
