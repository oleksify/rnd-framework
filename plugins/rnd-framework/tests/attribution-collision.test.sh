#!/usr/bin/env bash
# tests/attribution-collision.test.sh — Collision-proof attribution tests for
# lib/post-review-writer.sh.
#
# The defect this guards: the M<n>.T<nn> id scheme repeats T<nn> across
# milestones, so a substring match on a bare "T01" matched BOTH M1.T01 and
# M2.T01, and head -1 silently picked one (ordering-dependent). The fix: the
# manifest filename carries a globally-unique uuid, and the writer resolves the
# owning task by EXACTLY matching that uuid against features.json .uuid.
#
# Usage: bash tests/attribution-collision.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

WRITER="${PLUGIN_ROOT}/lib/post-review-writer.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Shared fixture builder: two tasks that COLLIDE on the bare T<nn> slot.
#   M1.T01 owns file A (uuid u1), shape "wiring".
#   M2.T01 owns file B (uuid u2), shape "data-transform".
# Manifests are named by the unique reference M<NN>-T<NN>-<uuid>-manifest.md so
# they do not overwrite each other.
#
# $1 = features.json task ordering: "m1-first" or "m2-first" (proves no head -1
#      ordering dependence).
# Echoes the session dir on stdout.
# ---------------------------------------------------------------------------

build_fixture() {
  local order="$1"
  local root="${TMP_DIR}/${order}"
  local session="${root}/session"
  local builds="${session}/builds"
  mkdir -p "$builds"

  cat > "${builds}/M01-T01-aaaa1111-manifest.md" <<'MD'
# Build Manifest: M01-T01-aaaa1111

## Files written
src/alpha.ts
MD

  cat > "${builds}/M02-T01-bbbb2222-manifest.md" <<'MD'
# Build Manifest: M02-T01-bbbb2222

## Files written
src/beta.ts
MD

  if [[ "$order" == "m2-first" ]]; then
    cat > "${session}/features.json" <<'JSON'
{
  "tasks": [
    { "id": "M2.T01.beta-task",  "uuid": "bbbb2222", "assertionIds": ["M2.area.b"] },
    { "id": "M1.T01.alpha-task", "uuid": "aaaa1111", "assertionIds": ["M1.area.a"] }
  ]
}
JSON
  else
    cat > "${session}/features.json" <<'JSON'
{
  "tasks": [
    { "id": "M1.T01.alpha-task", "uuid": "aaaa1111", "assertionIds": ["M1.area.a"] },
    { "id": "M2.T01.beta-task",  "uuid": "bbbb2222", "assertionIds": ["M2.area.b"] }
  ]
}
JSON
  fi

  cat > "${session}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.alpha-task","assertion_id":"M1.area.a","shape":"wiring","timestamp":"2026-05-30T08:00:00Z"}
{"event":"assertion_shape","task_id":"M2.T01.beta-task","assertion_id":"M2.area.b","shape":"data-transform","timestamp":"2026-05-30T08:00:01Z"}
JSONL

  printf '%s' "$session"
}

# Attribute one finding and echo the emitted shape.
#   $1 = session dir   $2 = slug dir   $3 = touched file
attribute() {
  local session="$1" slug="$2" file="$3"
  mkdir -p "$slug"
  CLAUDE_PLUGIN_DATA="$slug" "$WRITER" \
    --session-dir "$session" \
    --session-id  "20260530-090000-collide01" \
    --touched-file "$file" \
    --severity    "major" \
    --verifier-said-pass "true" \
    --review-found "true"
  jq -r '.shape' "${slug}/post-review.jsonl"
}

# ============================================================
# Test 1 — file A → M1.T01's shape (wiring); file B → M2.T01's shape.
# Neither cross-contaminates despite the shared T01 slot.
# ============================================================

printf '\n--- attribution-collision: file A and file B attribute distinctly ---\n'

SESSION="$(build_fixture m1-first)"

shape_a="$(attribute "$SESSION" "${TMP_DIR}/m1-first/slug-a" "src/alpha.ts")"
assert_eq "collision: file A → wiring (M1.T01)" "wiring" "$shape_a"

shape_b="$(attribute "$SESSION" "${TMP_DIR}/m1-first/slug-b" "src/beta.ts")"
assert_eq "collision: file B → data-transform (M2.T01)" "data-transform" "$shape_b"

# ============================================================
# Test 2 — reversing features.json task order does NOT change attribution.
# Proves no head -1 ordering dependence (the old defect).
# ============================================================

printf '\n--- attribution-collision: order-independent (no head -1) ---\n'

SESSION_REV="$(build_fixture m2-first)"

shape_a_rev="$(attribute "$SESSION_REV" "${TMP_DIR}/m2-first/slug-a" "src/alpha.ts")"
assert_eq "order-independent: file A → wiring even when M2 listed first" "wiring" "$shape_a_rev"

shape_b_rev="$(attribute "$SESSION_REV" "${TMP_DIR}/m2-first/slug-b" "src/beta.ts")"
assert_eq "order-independent: file B → data-transform even when M2 listed first" "data-transform" "$shape_b_rev"

# ============================================================
# Test 3 — a uuid that matches no task → graceful unattributable fallback.
# ============================================================

printf '\n--- attribution-collision: unmatched uuid → unattributable ---\n'

ORPHAN_SESSION="${TMP_DIR}/orphan/session"
ORPHAN_BUILDS="${ORPHAN_SESSION}/builds"
mkdir -p "$ORPHAN_BUILDS"

cat > "${ORPHAN_BUILDS}/M09-T09-deadbeef-manifest.md" <<'MD'
# Build Manifest: M09-T09-deadbeef

## Files written
src/orphan.ts
MD

cat > "${ORPHAN_SESSION}/features.json" <<'JSON'
{
  "tasks": [
    { "id": "M1.T01.alpha-task", "uuid": "aaaa1111", "assertionIds": ["M1.area.a"] }
  ]
}
JSON

cat > "${ORPHAN_SESSION}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.alpha-task","assertion_id":"M1.area.a","shape":"wiring","timestamp":"2026-05-30T08:00:00Z"}
JSONL

orphan_shape="$(attribute "$ORPHAN_SESSION" "${TMP_DIR}/orphan/slug" "src/orphan.ts")"
assert_eq "unmatched-uuid: file in manifest but uuid not in features → unattributable" "unattributable" "$orphan_shape"

report
