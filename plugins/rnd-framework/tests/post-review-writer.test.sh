#!/usr/bin/env bash
# tests/post-review-writer.test.sh — Tests for lib/post-review-writer.sh
# Usage: bash tests/post-review-writer.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

WRITER="${PLUGIN_ROOT}/lib/post-review-writer.sh"

# ---------------------------------------------------------------------------
# Temp environment: isolated slug-root (where post-review.jsonl is written)
# and a fake session dir with builds/, features.json, audit.jsonl.
# CLAUDE_PLUGIN_DATA → slug root (calibration.jsonl location and sibling
# post-review.jsonl are written here).
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SLUG_DIR="${TMP_DIR}/slug-root"
SESSION_DIR="${TMP_DIR}/session"
BUILDS_DIR="${SESSION_DIR}/builds"
mkdir -p "$SLUG_DIR" "$BUILDS_DIR"

POST_REVIEW="${SLUG_DIR}/post-review.jsonl"

# Write CLAUDE_PLUGIN_DATA to point at the slug root so the writer resolves
# post-review.jsonl as a sibling of calibration.jsonl in CLAUDE_PLUGIN_DATA.
export CLAUDE_PLUGIN_DATA="$SLUG_DIR"

# ============================================================
# Test 1 — all required fields present
# A single finding with a known file that matches a manifest.
# ============================================================

printf '\n--- post-review-writer: all-fields-present fixture ---\n'

# Write a manifest with ## Files written section
cat > "${BUILDS_DIR}/M01-T01-aaaa0001-manifest.md" <<'MD'
# Build Manifest: M01-T01-aaaa0001

## Files written
src/foo.ts
src/bar.ts
MD

# Write features.json mapping the task to assertion IDs
cat > "${SESSION_DIR}/features.json" <<'JSON'
{
  "tasks": [
    {
      "id": "M1.T01.some-task",
      "uuid": "aaaa0001",
      "assertionIds": ["M1.area.assertion-a", "M1.area.assertion-b"]
    }
  ]
}
JSON

# Write audit.jsonl with assertion_shape events for T01
cat > "${SESSION_DIR}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.some-task","assertion_id":"M1.area.assertion-a","shape":"wiring","timestamp":"2026-05-30T08:00:00Z"}
{"event":"assertion_shape","task_id":"M1.T01.some-task","assertion_id":"M1.area.assertion-b","shape":"wiring","timestamp":"2026-05-30T08:00:01Z"}
JSONL

# Invoke the writer: finding touches src/foo.ts (which is in T01's manifest)
"$WRITER" \
  --session-dir "$SESSION_DIR" \
  --session-id  "20260530-080000-abcd1234" \
  --touched-file "src/foo.ts" \
  --severity    "major" \
  --verifier-said-pass "true" \
  --review-found "true"

# Verify: one line in post-review.jsonl with all required fields
line_count="$(wc -l < "$POST_REVIEW" | tr -d ' ')"
assert_eq "all-fields: one line written" "1" "$line_count"

# jq -e: all 6 required fields present (verifier_said_PASS and review_found can be booleans)
field_check="$(jq -e '.shape and .severity and (.verifier_said_PASS != null) and (.review_found != null) and .session_id and .timestamp' "$POST_REVIEW")"
assert_eq "all-fields: jq -e all 6 fields truthy" "true" "$field_check"

# Verify file is at slug root (CLAUDE_PLUGIN_DATA)
assert_eq "all-fields: file at slug root" "$POST_REVIEW" "${SLUG_DIR}/post-review.jsonl"

# ============================================================
# Test 1b — path normalization (F1)
# An ABSOLUTE / differently-rooted touched-file still attributes to the
# manifest's repo-relative entry (component-aligned suffix), instead of
# silently falling through to "unattributable". A genuinely different path
# must still be unattributable (no over-broad match).
# ============================================================

printf '\n--- post-review-writer: path-normalization (F1) fixture ---\n'

# Reuse Test 1 fixtures: M01-T01 owns src/foo.ts → shape wiring.
: > "$POST_REVIEW"
"$WRITER" \
  --session-dir "$SESSION_DIR" \
  --session-id  "20260530-080000-abcd1234" \
  --touched-file "/Users/dev/project/src/foo.ts" \
  --severity    "minor" \
  --verifier-said-pass "true" \
  --review-found "true"
abs_shape="$(jq -r '.shape' "$POST_REVIEW")"
assert_eq "path-norm: absolute touched-file attributes (not unattributable)" "wiring" "$abs_shape"

: > "$POST_REVIEW"
"$WRITER" \
  --session-dir "$SESSION_DIR" \
  --session-id  "20260530-080000-abcd1234" \
  --touched-file "lib/elsewhere.ts" \
  --severity    "minor" \
  --verifier-said-pass "true" \
  --review-found "true"
unrelated_shape="$(jq -r '.shape' "$POST_REVIEW")"
assert_eq "path-norm: unrelated path stays unattributable" "unattributable" "$unrelated_shape"

# ============================================================
# Test 2 — shape attribution is mechanical
# A finding touching a file in a manifest → emitted shape equals
# the owning task's first assertion_shape in audit.jsonl.
# ============================================================

printf '\n--- post-review-writer: shape-attribution fixture ---\n'

# Reset state
TMP2_DIR="${TMP_DIR}/test2"
SESSION2_DIR="${TMP2_DIR}/session"
BUILDS2_DIR="${SESSION2_DIR}/builds"
SLUG2_DIR="${TMP2_DIR}/slug-root"
mkdir -p "$SLUG2_DIR" "$BUILDS2_DIR"

# Manifest: task owns lib/calibration.sh
cat > "${BUILDS2_DIR}/M01-T02-aaaa0002-manifest.md" <<'MD'
# Build Manifest: M01-T02-aaaa0002

## Files written
lib/calibration.sh
lib/other.sh
MD

# features.json: the task maps to two assertions
cat > "${SESSION2_DIR}/features.json" <<'JSON'
{
  "tasks": [
    {
      "id": "M1.T02.some-writer",
      "uuid": "aaaa0002",
      "assertionIds": ["M1.ledger.record-schema-fields-present", "M1.ledger.unattributable-findings-recorded"]
    }
  ]
}
JSON

# audit.jsonl: two shapes for T02 — data-transform comes first
cat > "${SESSION2_DIR}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T02.some-writer","assertion_id":"M1.ledger.record-schema-fields-present","shape":"data-transform","timestamp":"2026-05-30T08:00:00Z"}
{"event":"assertion_shape","task_id":"M1.T02.some-writer","assertion_id":"M1.ledger.unattributable-findings-recorded","shape":"data-transform","timestamp":"2026-05-30T08:00:01Z"}
JSONL

POST_REVIEW2="${SLUG2_DIR}/post-review.jsonl"

CLAUDE_PLUGIN_DATA="$SLUG2_DIR" "$WRITER" \
  --session-dir "$SESSION2_DIR" \
  --session-id  "20260530-081000-beef5678" \
  --touched-file "lib/calibration.sh" \
  --severity    "minor" \
  --verifier-said-pass "false" \
  --review-found "true"

emitted_shape="$(jq -r '.shape' "$POST_REVIEW2")"
assert_eq "attribution: emitted shape == data-transform" "data-transform" "$emitted_shape"

emitted_session="$(jq -r '.session_id' "$POST_REVIEW2")"
assert_eq "attribution: session_id recorded" "20260530-081000-beef5678" "$emitted_session"

# ============================================================
# Test 3 — unattributable: file in no manifest → shape:"unattributable"
# Zero findings dropped (input count == output count).
# ============================================================

printf '\n--- post-review-writer: unattributable fixture ---\n'

TMP3_DIR="${TMP_DIR}/test3"
SESSION3_DIR="${TMP3_DIR}/session"
BUILDS3_DIR="${SESSION3_DIR}/builds"
SLUG3_DIR="${TMP3_DIR}/slug-root"
mkdir -p "$SLUG3_DIR" "$BUILDS3_DIR"

# Manifest exists but does NOT include the finding's file
cat > "${BUILDS3_DIR}/M01-T01-aaaa0003-manifest.md" <<'MD'
# Build Manifest: M01-T01-aaaa0003

## Files written
src/known-file.ts
MD

cat > "${SESSION3_DIR}/features.json" <<'JSON'
{
  "tasks": [
    {
      "id": "M1.T01.known-task",
      "uuid": "aaaa0003",
      "assertionIds": ["M1.area.assertion-x"]
    }
  ]
}
JSON

cat > "${SESSION3_DIR}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.known-task","assertion_id":"M1.area.assertion-x","shape":"behaviour","timestamp":"2026-05-30T08:00:00Z"}
JSONL

POST_REVIEW3="${SLUG3_DIR}/post-review.jsonl"

# Finding touches a file NOT in any manifest
CLAUDE_PLUGIN_DATA="$SLUG3_DIR" "$WRITER" \
  --session-dir "$SESSION3_DIR" \
  --session-id  "20260530-082000-cafe9012" \
  --touched-file "some/orphan-file.sh" \
  --severity    "info" \
  --verifier-said-pass "true" \
  --review-found "true"

unattr_count="$(wc -l < "$POST_REVIEW3" | tr -d ' ')"
assert_eq "unattributable: exactly one record written" "1" "$unattr_count"

unattr_shape="$(jq -r '.shape' "$POST_REVIEW3")"
assert_eq "unattributable: shape is 'unattributable'" "unattributable" "$unattr_shape"

# ============================================================
# Test 4 — input count == output count (two findings, both recorded)
# One attributable + one unattributable = two output lines.
# ============================================================

printf '\n--- post-review-writer: count preservation (no drop) ---\n'

TMP4_DIR="${TMP_DIR}/test4"
SESSION4_DIR="${TMP4_DIR}/session"
BUILDS4_DIR="${SESSION4_DIR}/builds"
SLUG4_DIR="${TMP4_DIR}/slug-root"
mkdir -p "$SLUG4_DIR" "$BUILDS4_DIR"

cat > "${BUILDS4_DIR}/M01-T01-aaaa0004-manifest.md" <<'MD'
# Build Manifest: M01-T01-aaaa0004

## Files written
lib/foo.sh
MD

cat > "${SESSION4_DIR}/features.json" <<'JSON'
{
  "tasks": [
    {
      "id": "M1.T01.foo-task",
      "uuid": "aaaa0004",
      "assertionIds": ["M1.area.assertion-y"]
    }
  ]
}
JSON

cat > "${SESSION4_DIR}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.foo-task","assertion_id":"M1.area.assertion-y","shape":"wiring","timestamp":"2026-05-30T08:00:00Z"}
JSONL

POST_REVIEW4="${SLUG4_DIR}/post-review.jsonl"

# Finding 1: attributable
CLAUDE_PLUGIN_DATA="$SLUG4_DIR" "$WRITER" \
  --session-dir "$SESSION4_DIR" \
  --session-id  "20260530-083000-d00d3456" \
  --touched-file "lib/foo.sh" \
  --severity    "major" \
  --verifier-said-pass "true" \
  --review-found "true"

# Finding 2: unattributable
CLAUDE_PLUGIN_DATA="$SLUG4_DIR" "$WRITER" \
  --session-dir "$SESSION4_DIR" \
  --session-id  "20260530-083000-d00d3456" \
  --touched-file "some/external.py" \
  --severity    "minor" \
  --verifier-said-pass "false" \
  --review-found "true"

total_lines="$(wc -l < "$POST_REVIEW4" | tr -d ' ')"
assert_eq "count-preservation: 2 inputs → 2 output lines" "2" "$total_lines"

unattr_lines="$(jq -r 'select(.shape == "unattributable") | .shape' "$POST_REVIEW4" | wc -l | tr -d ' ')"
assert_eq "count-preservation: 1 unattributable line" "1" "$unattr_lines"

attr_lines="$(jq -r 'select(.shape != "unattributable") | .shape' "$POST_REVIEW4" | wc -l | tr -d ' ')"
assert_eq "count-preservation: 1 attributable line" "1" "$attr_lines"

# ============================================================
# Test 5 — clean-row mode: --clean-shape emits one clean row for the
# explicit shape WITHOUT attribution and WITHOUT --touched-file.
# ============================================================

printf '\n--- post-review-writer: clean-shape mode ---\n'

TMP5_DIR="${TMP_DIR}/test5"
SLUG5_DIR="${TMP5_DIR}/slug-root"
mkdir -p "$SLUG5_DIR"

POST_REVIEW5="${SLUG5_DIR}/post-review.jsonl"

# No session dir / manifest / features.json / audit.jsonl provided: the clean
# path must not require any attribution input.
CLAUDE_PLUGIN_DATA="$SLUG5_DIR" "$WRITER" \
  --session-id  "20260530-084000-feed7890" \
  --clean-shape "wiring"

clean_count="$(wc -l < "$POST_REVIEW5" | tr -d ' ')"
assert_eq "clean-shape: exactly one record written" "1" "$clean_count"

clean_shape="$(jq -r '.shape' "$POST_REVIEW5")"
assert_eq "clean-shape: shape == wiring" "wiring" "$clean_shape"

clean_review_found="$(jq -r '.review_found' "$POST_REVIEW5")"
assert_eq "clean-shape: review_found == false" "false" "$clean_review_found"

clean_session="$(jq -r '.session_id' "$POST_REVIEW5")"
assert_eq "clean-shape: session_id recorded" "20260530-084000-feed7890" "$clean_session"

# Clean rows must carry a clean-distinct severity, never the finding-severity
# "info" — overloading "info" would conflate clean runs with info findings.
clean_severity="$(jq -r '.severity' "$POST_REVIEW5")"
assert_eq "clean-shape: severity is clean-distinct (not info)" "none" "$clean_severity"

# Required fields still present so the Section 8 view can read the row.
clean_fields="$(jq -e '.shape and .severity and (.verifier_said_PASS != null) and (.review_found != null) and .session_id and .timestamp' "$POST_REVIEW5")"
assert_eq "clean-shape: all consumed fields truthy" "true" "$clean_fields"

# ============================================================
# Test 6 — clean-row mode rejects a shape outside x-shape-vocab.
# ============================================================

printf '\n--- post-review-writer: clean-shape invalid rejected ---\n'

TMP6_DIR="${TMP_DIR}/test6"
SLUG6_DIR="${TMP6_DIR}/slug-root"
mkdir -p "$SLUG6_DIR"

POST_REVIEW6="${SLUG6_DIR}/post-review.jsonl"

set +e
CLAUDE_PLUGIN_DATA="$SLUG6_DIR" "$WRITER" \
  --session-id  "20260530-085000-baad0001" \
  --clean-shape "not-a-real-shape" 2>/dev/null
invalid_exit=$?
set -e

assert_eq "clean-shape: invalid shape exits non-zero" "1" "$invalid_exit"

invalid_written="0"
[[ -f "$POST_REVIEW6" ]] && invalid_written="$(wc -l < "$POST_REVIEW6" | tr -d ' ')"
assert_eq "clean-shape: invalid shape writes no record" "0" "$invalid_written"

report
