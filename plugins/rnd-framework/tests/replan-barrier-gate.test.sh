#!/usr/bin/env bash
# tests/replan-barrier-gate.test.sh — Tests for the re-plan information barrier.
#
# Exercises is_replan_artifact_violation (lib.sh), its wiring into read-gate.sh
# and glob-grep-gate.sh, and confirms write-gate.sh is NOT affected.
#
# The barrier fires only when ALL of:
#   - agent_type (lowered) contains "planner"
#   - a marker file `$session_dir/.replan-in-progress` exists
#   - the read target equals one of the four canonical artifacts at the session root
#
# Archived paths under `prior-plans/replan-*/` are out of scope by design — the
# differ reads from there, and a freshly-spawned planner can also look at the
# archive if it really wants (we discourage that via the spawn prompt, not the
# barrier).
#
# Usage: bash tests/replan-barrier-gate.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

READ_GATE="${SCRIPT_DIR}/../hooks/read-gate.sh"
GLOB_GREP_GATE="${SCRIPT_DIR}/../hooks/glob-grep-gate.sh"
WRITE_GATE="${SCRIPT_DIR}/../hooks/write-gate.sh"
LIB="${SCRIPT_DIR}/../hooks/lib.sh"

# ---------------------------------------------------------------------------
# Fixture: build a fake CLAUDE_CONFIG_DIR layout with an active session and a
# re-plan marker file. The active-base-dir cache lets active_session_dir()
# resolve without invoking rnd-dir.sh.
# ---------------------------------------------------------------------------

FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

CONFIG_DIR="${FIXTURE_ROOT}/.claude"
BASE_DIR="${CONFIG_DIR}/.rnd/test-slug/branches/main"
SESSION_ID="20260528-120000-deadbeef"
SESSION_DIR="${BASE_DIR}/sessions/${SESSION_ID}"
PRIOR_DIR="${SESSION_DIR}/prior-plans/replan-1"

mkdir -p "${CONFIG_DIR}/.rnd"
mkdir -p "${SESSION_DIR}"
mkdir -p "${PRIOR_DIR}"
printf '%s' "$BASE_DIR" > "${CONFIG_DIR}/.rnd/.active-base-dir"
printf '%s' "$SESSION_ID" > "${BASE_DIR}/.current-session"

# Create the canonical artifacts so realpath/identity checks succeed.
for f in protocol.md validation-contract.md features.json AGENTS.md; do
  printf 'placeholder\n' > "${SESSION_DIR}/${f}"
  printf 'archived placeholder\n' > "${PRIOR_DIR}/${f}"
done

CANONICAL_PROTOCOL="${SESSION_DIR}/protocol.md"
CANONICAL_CONTRACT="${SESSION_DIR}/validation-contract.md"
CANONICAL_FEATURES="${SESSION_DIR}/features.json"
CANONICAL_AGENTS="${SESSION_DIR}/AGENTS.md"
ARCHIVED_PROTOCOL="${PRIOR_DIR}/protocol.md"

MARKER="${SESSION_DIR}/.replan-in-progress"

# All hooks read CLAUDE_CONFIG_DIR to resolve the artifact tree.
export CLAUDE_CONFIG_DIR="$CONFIG_DIR"

set_marker()   { : > "$MARKER"; }
unset_marker() { rm -f "$MARKER"; }

mk_read_input() {
  # $1 = file_path, $2 = agent_type
  printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"agent_type":"%s"}' "$1" "$2"
}

mk_glob_input() {
  # $1 = path, $2 = pattern, $3 = agent_type
  printf '{"tool_name":"Glob","tool_input":{"path":"%s","pattern":"%s"},"agent_type":"%s"}' "$1" "$2" "$3"
}

mk_write_input() {
  # $1 = file_path, $2 = agent_type
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"},"agent_type":"%s"}' "$1" "$2"
}

# ---------------------------------------------------------------------------
# Pure-predicate tests (lib.sh): exercise is_replan_artifact_violation in
# isolation, before testing the gate wiring.
# ---------------------------------------------------------------------------

# shellcheck source=../hooks/lib.sh
source "$LIB"

printf '%s\n' '--- is_replan_artifact_violation (pure) ---'

set_marker

# (a) planner + marker + canonical → violation
if is_replan_artifact_violation "$CANONICAL_PROTOCOL" "rnd-planner"; then
  assert_eq "predicate: planner+marker+canonical → violation (returns 0)" "0" "0"
else
  assert_eq "predicate: planner+marker+canonical → violation (returns 0)" "0" "1"
fi

# Each canonical artifact triggers the violation.
for cf in "$CANONICAL_CONTRACT" "$CANONICAL_FEATURES" "$CANONICAL_AGENTS"; do
  if is_replan_artifact_violation "$cf" "rnd-planner"; then
    assert_eq "predicate: canonical $(basename "$cf") triggers violation" "0" "0"
  else
    assert_eq "predicate: canonical $(basename "$cf") triggers violation" "0" "1"
  fi
done

# Archived path is NOT a violation (barrier protects canonical paths only).
if is_replan_artifact_violation "$ARCHIVED_PROTOCOL" "rnd-planner"; then
  assert_eq "predicate: planner+marker+archived → no violation" "1" "0"
else
  assert_eq "predicate: planner+marker+archived → no violation" "1" "1"
fi

# Differ contains "rep" but NOT "planner" → no violation, even on canonical.
if is_replan_artifact_violation "$CANONICAL_PROTOCOL" "rnd-replan-differ"; then
  assert_eq "predicate: differ+marker+canonical → no violation" "1" "0"
else
  assert_eq "predicate: differ+marker+canonical → no violation" "1" "1"
fi

# Empty agent_type (orchestrator) → no violation.
if is_replan_artifact_violation "$CANONICAL_PROTOCOL" ""; then
  assert_eq "predicate: orchestrator+marker+canonical → no violation" "1" "0"
else
  assert_eq "predicate: orchestrator+marker+canonical → no violation" "1" "1"
fi

# Marker absent → no violation, even for planner on canonical.
unset_marker
if is_replan_artifact_violation "$CANONICAL_PROTOCOL" "rnd-planner"; then
  assert_eq "predicate: planner+NO-marker+canonical → no violation" "1" "0"
else
  assert_eq "predicate: planner+NO-marker+canonical → no violation" "1" "1"
fi
set_marker

# Random path → no violation.
if is_replan_artifact_violation "/tmp/whatever.md" "rnd-planner"; then
  assert_eq "predicate: planner+marker+random path → no violation" "1" "0"
else
  assert_eq "predicate: planner+marker+random path → no violation" "1" "1"
fi

# ---------------------------------------------------------------------------
# read-gate.sh end-to-end
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- read-gate.sh ---'

# (a) planner + marker + canonical → BLOCK with RE-PLAN BARRIER
set_marker
run_hook "$READ_GATE" "$(mk_read_input "$CANONICAL_PROTOCOL" "rnd-planner")"
assert_exit_code "read-gate: planner+marker+canonical protocol.md → exit 2" 2
assert_contains  "read-gate: planner+marker+canonical → stderr RE-PLAN BARRIER" "RE-PLAN BARRIER" "$HOOK_STDERR"

for cf in "$CANONICAL_CONTRACT" "$CANONICAL_FEATURES" "$CANONICAL_AGENTS"; do
  run_hook "$READ_GATE" "$(mk_read_input "$cf" "rnd-planner")"
  assert_exit_code "read-gate: planner+marker+canonical $(basename "$cf") → exit 2" 2
done

# (b) differ + marker + canonical → ALLOW (auto-allow JSON, since under .rnd/)
run_hook "$READ_GATE" "$(mk_read_input "$CANONICAL_PROTOCOL" "rnd-replan-differ")"
assert_exit_code "read-gate: differ+marker+canonical → exit 0" 0
assert_contains  "read-gate: differ+marker+canonical → allow JSON" '"permissionDecision":"allow"' "$HOOK_STDOUT"

# (c) differ + marker + archived → ALLOW (auto-allow, under .rnd/)
run_hook "$READ_GATE" "$(mk_read_input "$ARCHIVED_PROTOCOL" "rnd-replan-differ")"
assert_exit_code "read-gate: differ+marker+archived → exit 0" 0
assert_contains  "read-gate: differ+marker+archived → allow JSON" '"permissionDecision":"allow"' "$HOOK_STDOUT"

# (d) planner + marker + archived → ALLOW (barrier is canonical-only)
run_hook "$READ_GATE" "$(mk_read_input "$ARCHIVED_PROTOCOL" "rnd-planner")"
assert_exit_code "read-gate: planner+marker+archived → exit 0" 0
assert_contains  "read-gate: planner+marker+archived → allow JSON (under .rnd/)" '"permissionDecision":"allow"' "$HOOK_STDOUT"

# (e) planner + NO marker + canonical → ALLOW (happy path, no re-plan in progress)
unset_marker
run_hook "$READ_GATE" "$(mk_read_input "$CANONICAL_PROTOCOL" "rnd-planner")"
assert_exit_code "read-gate: planner+NO-marker+canonical → exit 0" 0
assert_contains  "read-gate: planner+NO-marker+canonical → allow JSON" '"permissionDecision":"allow"' "$HOOK_STDOUT"

# Orchestrator (empty agent) + marker + canonical → ALLOW.
set_marker
run_hook "$READ_GATE" "$(mk_read_input "$CANONICAL_PROTOCOL" "")"
assert_exit_code "read-gate: orchestrator+marker+canonical → exit 0" 0

# Existing barrier still fires: verifier reading self-assessment is blocked, even with no marker bearing.
run_hook "$READ_GATE" "$(mk_read_input "${SESSION_DIR}/builds/T1-self-assessment.md" "rnd-verifier")"
assert_exit_code "read-gate: verifier+self-assessment → still blocked (regression)" 2

# ---------------------------------------------------------------------------
# glob-grep-gate.sh: path / pattern / concatenation smuggling defense
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- glob-grep-gate.sh ---'

# Canonical artifact in `path` field → BLOCK.
run_hook "$GLOB_GREP_GATE" "$(mk_glob_input "$CANONICAL_PROTOCOL" "*.md" "rnd-planner")"
assert_exit_code "glob: planner+marker+canonical in path → exit 2" 2
assert_contains  "glob: planner+marker+canonical in path → stderr RE-PLAN BARRIER" "RE-PLAN BARRIER" "$HOOK_STDERR"

# Canonical artifact in `pattern` field → BLOCK.
run_hook "$GLOB_GREP_GATE" "$(mk_glob_input "/tmp" "$CANONICAL_PROTOCOL" "rnd-planner")"
assert_exit_code "glob: planner+marker+canonical in pattern → exit 2" 2

# Smuggling: split path + pattern across the two fields → BLOCK.
SMUGGLE_PATH="${SESSION_DIR}"
SMUGGLE_PATTERN="/protocol.md"
run_hook "$GLOB_GREP_GATE" "$(mk_glob_input "$SMUGGLE_PATH" "$SMUGGLE_PATTERN" "rnd-planner")"
assert_exit_code "glob: smuggled path+pattern split → exit 2" 2
assert_contains  "glob: smuggled split → stderr RE-PLAN BARRIER" "RE-PLAN BARRIER" "$HOOK_STDERR"

# Differ should not be blocked by the smuggle defense.
run_hook "$GLOB_GREP_GATE" "$(mk_glob_input "$SMUGGLE_PATH" "$SMUGGLE_PATTERN" "rnd-replan-differ")"
assert_exit_code "glob: differ+smuggled split → exit 0" 0

# Planner without marker → not blocked.
unset_marker
run_hook "$GLOB_GREP_GATE" "$(mk_glob_input "$CANONICAL_PROTOCOL" "*.md" "rnd-planner")"
assert_exit_code "glob: planner+NO-marker+canonical → exit 0" 0
set_marker

# ---------------------------------------------------------------------------
# write-gate.sh — parallel coverage: the barrier must NOT extend to writes.
# The Planner must still be able to produce the new canonical plan.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- write-gate.sh (untouched by re-plan barrier) ---'

run_hook "$WRITE_GATE" "$(mk_write_input "$CANONICAL_PROTOCOL" "rnd-planner")"
assert_exit_code "write-gate: planner+marker+canonical Write → not blocked by re-plan barrier" 0

run_hook "$WRITE_GATE" "$(mk_write_input "$CANONICAL_FEATURES" "rnd-planner")"
assert_exit_code "write-gate: planner+marker+canonical features.json Write → not blocked" 0

# Predicate name must be absent from write-gate.sh source (asserted by static grep).
if grep -q 'is_replan_artifact_violation' "$WRITE_GATE"; then
  assert_eq "write-gate.sh does NOT reference is_replan_artifact_violation" "absent" "present"
else
  assert_eq "write-gate.sh does NOT reference is_replan_artifact_violation" "absent" "absent"
fi

# ---------------------------------------------------------------------------
# Single-definition: predicate defined exactly once in lib.sh, called by both
# read-gate.sh and glob-grep-gate.sh.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- structural: single-definition + call sites ---'

def_count="$(grep -cE '^is_replan_artifact_violation\(\)' "$LIB" || true)"
assert_eq "lib.sh defines is_replan_artifact_violation() exactly once" "1" "$def_count"

if grep -q 'is_replan_artifact_violation' "$READ_GATE"; then
  assert_eq "read-gate.sh calls is_replan_artifact_violation" "yes" "yes"
else
  assert_eq "read-gate.sh calls is_replan_artifact_violation" "yes" "no"
fi

if grep -q 'is_replan_artifact_violation' "$GLOB_GREP_GATE"; then
  assert_eq "glob-grep-gate.sh calls is_replan_artifact_violation" "yes" "yes"
else
  assert_eq "glob-grep-gate.sh calls is_replan_artifact_violation" "yes" "no"
fi

report
