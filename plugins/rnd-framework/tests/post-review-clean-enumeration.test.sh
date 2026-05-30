#!/usr/bin/env bash
# tests/post-review-clean-enumeration.test.sh
#
# Exercises the clean-review enumeration documented in Phase 8 of
# commands/rnd-start.md: on a clean review, derive the session's DISTINCT
# in-scope shapes from audit.jsonl `assertion_shape` events and call the
# writer's --clean-shape mode once per distinct shape.
#
# This test runs the exact jq enumeration + writer wiring the orchestrator
# executes, so a regression in either the enumeration or the writer is caught.
#
# Usage: bash tests/post-review-clean-enumeration.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

WRITER="${PLUGIN_ROOT}/lib/post-review-writer.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# The enumeration the orchestrator runs in Phase 8's clean path: distinct
# shapes from assertion_shape events, fed one-per-line into the writer.
clean_emit_per_shape() {
  local session_dir="$1"
  local session_id="$2"
  local audit_file="${session_dir}/audit.jsonl"

  [[ -f "$audit_file" ]] || return 0

  jq -r 'select(.event == "assertion_shape") | .shape' "$audit_file" \
    | sort -u \
    | while IFS= read -r shape; do
        [[ -n "$shape" ]] || continue
        "$WRITER" \
          --session-id  "$session_id" \
          --clean-shape "$shape"
      done
}

# ============================================================
# Test 1 — two distinct in-scope shapes → two clean rows, one per shape,
# zero unattributable.
# ============================================================

printf '\n--- clean-enumeration: two distinct shapes ---\n'

SESSION_DIR="${TMP_DIR}/session"
SLUG_DIR="${TMP_DIR}/slug-root"
mkdir -p "$SESSION_DIR" "$SLUG_DIR"

POST_REVIEW="${SLUG_DIR}/post-review.jsonl"

# audit.jsonl carries assertion_shape events for two distinct shapes
# (wiring appears twice to prove distinctness collapses duplicates).
cat > "${SESSION_DIR}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.a","assertion_id":"M1.x.a","shape":"wiring","timestamp":"2026-05-30T08:00:00Z"}
{"event":"assertion_shape","task_id":"M1.T01.a","assertion_id":"M1.x.b","shape":"wiring","timestamp":"2026-05-30T08:00:01Z"}
{"event":"assertion_shape","task_id":"M1.T02.b","assertion_id":"M1.y.a","shape":"data-transform","timestamp":"2026-05-30T08:00:02Z"}
{"event":"builder_self_assessment","task_id":"M1.T01.a","self_verdict":"DONE","timestamp":"2026-05-30T08:00:03Z"}
JSONL

CLAUDE_PLUGIN_DATA="$SLUG_DIR" clean_emit_per_shape "$SESSION_DIR" "20260530-080000-aaaa1111"

total_rows="$(wc -l < "$POST_REVIEW" | tr -d ' ')"
assert_eq "two-shapes: exactly two clean rows written" "2" "$total_rows"

distinct_shapes="$(jq -r '.shape' "$POST_REVIEW" | sort -u | wc -l | tr -d ' ')"
assert_eq "two-shapes: two distinct shapes" "2" "$distinct_shapes"

wiring_rows="$(jq -r 'select(.shape == "wiring") | .shape' "$POST_REVIEW" | wc -l | tr -d ' ')"
assert_eq "two-shapes: one wiring row (duplicates collapsed)" "1" "$wiring_rows"

dt_rows="$(jq -r 'select(.shape == "data-transform") | .shape' "$POST_REVIEW" | wc -l | tr -d ' ')"
assert_eq "two-shapes: one data-transform row" "1" "$dt_rows"

unattr_rows="$(jq -r 'select(.shape == "unattributable") | .shape' "$POST_REVIEW" | wc -l | tr -d ' ')"
assert_eq "two-shapes: zero unattributable rows" "0" "$unattr_rows"

all_clean="$(jq -s 'all(.[]; .review_found == false)' "$POST_REVIEW")"
assert_eq "two-shapes: every row review_found:false" "true" "$all_clean"

# ============================================================
# Test 2 — degenerate fallback: a clean session with ZERO assertion_shape
# events emits no per-shape rows (the documented degenerate case).
# ============================================================

printf '\n--- clean-enumeration: zero in-scope shapes ---\n'

SESSION2_DIR="${TMP_DIR}/session2"
SLUG2_DIR="${TMP_DIR}/slug-root2"
mkdir -p "$SESSION2_DIR" "$SLUG2_DIR"

POST_REVIEW2="${SLUG2_DIR}/post-review.jsonl"

# audit.jsonl with no assertion_shape events at all.
cat > "${SESSION2_DIR}/audit.jsonl" <<'JSONL'
{"event":"builder_self_assessment","task_id":"M1.T01.a","self_verdict":"DONE","timestamp":"2026-05-30T08:00:00Z"}
JSONL

CLAUDE_PLUGIN_DATA="$SLUG2_DIR" clean_emit_per_shape "$SESSION2_DIR" "20260530-081000-bbbb2222"

zero_rows="0"
[[ -f "$POST_REVIEW2" ]] && zero_rows="$(wc -l < "$POST_REVIEW2" | tr -d ' ')"
assert_eq "zero-shapes: no per-shape clean rows emitted" "0" "$zero_rows"

report
