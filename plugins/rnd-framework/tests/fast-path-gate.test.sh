#!/usr/bin/env bash
# Tests: the Shape-Validity Fast Path dispatch gate is documented consistently in
# the orchestration skill and the rnd-start Phase 2 build prompt, and that its
# load-bearing imperatives (verification always runs, HIGH never fast-paths, the
# manifest is always written, one-strike demotion via recomputation) are present
# and greppable so the no-slop floor is checkable.
# Usage: bash tests/fast-path-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

ORCHESTRATION="${SCRIPT_DIR}/../skills/rnd-orchestration/SKILL.md"
RND_START="${SCRIPT_DIR}/../commands/rnd-start.md"
CALIBRATION="${SCRIPT_DIR}/../lib/calibration.sh"

grep_file() {
  grep -qE "$1" "$2"
}

assert_grep() {
  local desc="$1" pattern="$2" file="$3"
  assert_eq "$desc" "pass" "$(grep_file "$pattern" "$file" && printf pass || printf fail)"
}

refute_grep() {
  local desc="$1" pattern="$2" file="$3"
  assert_eq "$desc" "pass" "$(grep_file "$pattern" "$file" && printf fail || printf pass)"
}

# ---------------------------------------------------------------------------
# Orchestration skill — gate subsection present, positioned after the
# Calibration Auto-Escalation gate, before Stop Conditions.
# ---------------------------------------------------------------------------

printf '%s\n' '--- orchestration skill: Shape-Validity Fast Path gate ---'

assert_grep \
  "orchestration skill: Shape-Validity Fast Path heading present" \
  "### Shape-Validity Fast Path" \
  "$ORCHESTRATION"

# Heading order: Calibration Auto-Escalation < Shape-Validity Fast Path < Stop Conditions
fastpath_line="$(grep -n "### Shape-Validity Fast Path" "$ORCHESTRATION" | head -1 | cut -d: -f1)"
escalation_line="$(grep -n "### Calibration Auto-Escalation" "$ORCHESTRATION" | head -1 | cut -d: -f1)"
stop_line="$(grep -n "^## Stop Conditions" "$ORCHESTRATION" | head -1 | cut -d: -f1)"

assert_eq "orchestration skill: fast path is AFTER Calibration Auto-Escalation" \
  "pass" \
  "$([[ "$fastpath_line" -gt "$escalation_line" ]] && printf pass || printf fail)"

assert_eq "orchestration skill: fast path is BEFORE Stop Conditions" \
  "pass" \
  "$([[ "$fastpath_line" -lt "$stop_line" ]] && printf pass || printf fail)"

# ---------------------------------------------------------------------------
# Orchestration skill — the gate calls the validity helper and mirrors the
# should_promote exit-code branch structure.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- orchestration skill: helper call + exit-code branch ---'

assert_grep \
  "orchestration skill: calls calibration.sh validity" \
  "calibration\.sh\" validity" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: branches on expert vs novice" \
  "expert" \
  "$ORCHESTRATION"

# ---------------------------------------------------------------------------
# Orchestration skill — the three no-slop-floor imperatives.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- orchestration skill: no-slop-floor imperatives ---'

assert_grep \
  "orchestration skill: verification ALWAYS runs" \
  "[Vv]erification ALWAYS runs" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: HIGH never fast-paths (hard floor)" \
  "HIGH (NEVER|never) fast-path" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: builder STILL writes a Files written manifest" \
  "STILL writes a .## Files written. manifest" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: single build-verify pass" \
  "[Ss]ingle build-verify pass|SINGLE build-verify pass" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: models stay at the criticality tier (no tier drop)" \
  "[Mm]odels stay at the criticality tier" \
  "$ORCHESTRATION"

# ---------------------------------------------------------------------------
# Orchestration skill — one-strike demotion via recomputation, no shadow record.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- orchestration skill: one-strike demotion via recomputation ---'

assert_grep \
  "orchestration skill: one-strike demotion is via recomputation" \
  "[Rr]ecomputation" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: reads validity live on every dispatch" \
  "live on every dispatch|live each dispatch|on every dispatch" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: no shadow/separate demotion record" \
  "shadow record|separate demotion" \
  "$ORCHESTRATION"

# ---------------------------------------------------------------------------
# Orchestration skill — skip-condition table covers expert+HIGH → full path.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- orchestration skill: skip-condition table ---'

assert_grep \
  "orchestration skill: table row expert + HIGH → full path" \
  "expert.*HIGH.*full path" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: table row expert + LOW → fast profile" \
  "expert.*LOW.*fast profile" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: table row novice → full path" \
  "novice.*full path|non-expert.*full path" \
  "$ORCHESTRATION"

# ---------------------------------------------------------------------------
# rnd-start.md Phase 2 — the pre-spawn gate text mirrors the skill.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- rnd-start.md Phase 2: pre-spawn fast-path gate ---'

assert_grep \
  "rnd-start: fast-path gate documented in Phase 2 build" \
  "fast.path gate|Shape-validity fast-path|fast profile" \
  "$RND_START"

assert_grep \
  "rnd-start: calls calibration.sh validity" \
  "calibration\.sh\" validity" \
  "$RND_START"

assert_grep \
  "rnd-start: HIGH never fast-paths" \
  "HIGH (NEVER|never) fast-path" \
  "$RND_START"

assert_grep \
  "rnd-start: verification ALWAYS runs" \
  "[Vv]erification ALWAYS runs" \
  "$RND_START"

assert_grep \
  "rnd-start: builder STILL writes a Files written manifest" \
  "STILL writes a .## Files written. manifest" \
  "$RND_START"

assert_grep \
  "rnd-start: models stay at the criticality tier (no tier drop)" \
  "[Mm]odels stay at the criticality tier" \
  "$RND_START"

assert_grep \
  "rnd-start: one-strike demotion via recomputation" \
  "[Rr]ecomputation" \
  "$RND_START"

# ---------------------------------------------------------------------------
# Interface consistency — the validity subcommand the prose calls actually
# exists with the documented expert/novice exit-code contract.
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- calibration.sh: validity subcommand exists ---'

assert_grep \
  "calibration.sh: validity case arm present" \
  "validity\)" \
  "$CALIBRATION"

# Live contract: 5 clean → expert (exit 0); +1 dirty → novice (exit 1), no state write.
TMPDIR_FP="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_FP"' EXIT
PR="${TMPDIR_FP}/post-review.jsonl"
for i in 1 2 3 4 5; do
  printf '{"shape":"wiring","review_found":false,"session_id":"2026010%d-000000-aaaa","timestamp":"2026-01-0%dT00:00:00Z"}\n' "$i" "$i" >> "$PR"
done

expert_out="$(CLAUDE_PLUGIN_DATA="$TMPDIR_FP" bash "$CALIBRATION" validity wiring 2>&1)"
expert_rc=$?
assert_eq "calibration.sh: 5 clean → expert" "expert" "$expert_out"
assert_eq "calibration.sh: 5 clean → exit 0" "0" "$expert_rc"

printf '{"shape":"wiring","review_found":true,"severity":"high","session_id":"20260106-000000-aaaa","timestamp":"2026-01-06T00:00:00Z"}\n' >> "$PR"
novice_out="$(CLAUDE_PLUGIN_DATA="$TMPDIR_FP" bash "$CALIBRATION" validity wiring 2>&1 || true)"
CLAUDE_PLUGIN_DATA="$TMPDIR_FP" bash "$CALIBRATION" validity wiring >/dev/null 2>&1 && novice_rc=0 || novice_rc=1
assert_eq "calibration.sh: one-strike → novice 0" "novice 0" "$novice_out"
assert_eq "calibration.sh: one-strike → exit non-zero" "1" "$novice_rc"

# ---------------------------------------------------------------------------
report
