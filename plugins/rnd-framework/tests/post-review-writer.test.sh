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

# ============================================================
# Test 7 — verifier_said_PASS is DERIVED from the owning task's verdict (F3).
#
# The writer aggregates the owning task's entries in
# verifications/wave-*-verdict-map.json (PASS iff none is FAIL/NEEDS_ITERATION)
# and the derived value WINS over the --verifier-said-pass flag for an
# attributed finding. An unattributable finding (no owning task / no verdict
# map) falls back to the flag.
# ============================================================

printf '\n--- post-review-writer: verifier_said_PASS derived from verdict (F3) ---\n'

# Shared fixture: M01-T07 owns lib/derived.sh, shape wiring.
make_f3_fixture() {
  local root="$1"
  local session="${root}/session"
  local builds="${session}/builds"
  local verif="${session}/verifications"
  mkdir -p "$builds" "$verif"

  cat > "${builds}/M01-T07-cccc0007-manifest.md" <<'MD'
# Build Manifest: M01-T07-cccc0007

## Files written
lib/derived.sh
MD

  cat > "${session}/features.json" <<'JSON'
{
  "tasks": [
    { "id": "M1.T07.derived-task", "uuid": "cccc0007", "assertionIds": ["M1.area.d1", "M1.area.d2"] }
  ]
}
JSON

  cat > "${session}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T07.derived-task","assertion_id":"M1.area.d1","shape":"wiring","timestamp":"2026-05-30T08:00:00Z"}
JSONL

  printf '%s' "$session"
}

# --- 7a: owning task aggregates to NEEDS_ITERATION → false, even with flag true ---
F3A_DIR="${TMP_DIR}/f3a"
F3A_SESSION="$(make_f3_fixture "$F3A_DIR")"
cat > "${F3A_SESSION}/verifications/wave-1-verdict-map.json" <<'JSON'
{
  "M1.area.d1": { "verdict": "PASS",            "evidence": ["x"], "feedback": "", "task_id": "M1.T07.derived-task" },
  "M1.area.d2": { "verdict": "NEEDS_ITERATION", "evidence": ["y"], "feedback": "", "task_id": "M1.T07.derived-task" }
}
JSON

F3A_SLUG="${F3A_DIR}/slug"
mkdir -p "$F3A_SLUG"
CLAUDE_PLUGIN_DATA="$F3A_SLUG" "$WRITER" \
  --session-dir "$F3A_SESSION" \
  --session-id  "20260530-086000-f3a00001" \
  --touched-file "lib/derived.sh" \
  --severity    "major" \
  --verifier-said-pass "true" \
  --review-found "true"

f3a_pass="$(jq -r '.verifier_said_PASS' "${F3A_SLUG}/post-review.jsonl")"
assert_eq "F3: NEEDS_ITERATION owning task → false even when flag true" "false" "$f3a_pass"

# --- 7b: owning task all-PASS → true (regardless of flag) ---
F3B_DIR="${TMP_DIR}/f3b"
F3B_SESSION="$(make_f3_fixture "$F3B_DIR")"
cat > "${F3B_SESSION}/verifications/wave-1-verdict-map.json" <<'JSON'
{
  "M1.area.d1": { "verdict": "PASS",                          "evidence": ["x"], "feedback": "", "task_id": "M1.T07.derived-task" },
  "M1.area.d2": { "verdict": "PASS_QUALITY_NEEDS_ITERATION",  "evidence": ["y"], "feedback": "", "task_id": "M1.T07.derived-task" }
}
JSON

F3B_SLUG="${F3B_DIR}/slug"
mkdir -p "$F3B_SLUG"
CLAUDE_PLUGIN_DATA="$F3B_SLUG" "$WRITER" \
  --session-dir "$F3B_SESSION" \
  --session-id  "20260530-086100-f3b00001" \
  --touched-file "lib/derived.sh" \
  --severity    "minor" \
  --verifier-said-pass "false" \
  --review-found "true"

f3b_pass="$(jq -r '.verifier_said_PASS' "${F3B_SLUG}/post-review.jsonl")"
assert_eq "F3: all-PASS owning task → true even when flag false" "true" "$f3b_pass"

# --- 7c: unattributable finding (no owning task, no map entry) → flag fallback ---
F3C_DIR="${TMP_DIR}/f3c"
F3C_SESSION="$(make_f3_fixture "$F3C_DIR")"
# No verdict map at all; finding touches a file in no manifest.
F3C_SLUG="${F3C_DIR}/slug"
mkdir -p "$F3C_SLUG"
CLAUDE_PLUGIN_DATA="$F3C_SLUG" "$WRITER" \
  --session-dir "$F3C_SESSION" \
  --session-id  "20260530-086200-f3c00001" \
  --touched-file "some/unowned-file.ts" \
  --severity    "info" \
  --verifier-said-pass "true" \
  --review-found "true"

f3c_shape="$(jq -r '.shape' "${F3C_SLUG}/post-review.jsonl")"
assert_eq "F3: unattributable finding stays unattributable" "unattributable" "$f3c_shape"

f3c_pass="$(jq -r '.verifier_said_PASS' "${F3C_SLUG}/post-review.jsonl")"
assert_eq "F3: unattributable finding falls back to flag (true)" "true" "$f3c_pass"

# --- 7d: attributed finding but owning task has NO verdict-map entry → flag fallback ---
F3D_DIR="${TMP_DIR}/f3d"
F3D_SESSION="$(make_f3_fixture "$F3D_DIR")"
# Verdict map present but for a DIFFERENT task — no entry for M1.T07.derived-task.
cat > "${F3D_SESSION}/verifications/wave-1-verdict-map.json" <<'JSON'
{
  "M9.area.z": { "verdict": "FAIL", "evidence": ["z"], "feedback": "", "task_id": "M9.T99.other-task" }
}
JSON

F3D_SLUG="${F3D_DIR}/slug"
mkdir -p "$F3D_SLUG"
CLAUDE_PLUGIN_DATA="$F3D_SLUG" "$WRITER" \
  --session-dir "$F3D_SESSION" \
  --session-id  "20260530-086300-f3d00001" \
  --touched-file "lib/derived.sh" \
  --severity    "minor" \
  --verifier-said-pass "false" \
  --review-found "true"

f3d_pass="$(jq -r '.verifier_said_PASS' "${F3D_SLUG}/post-review.jsonl")"
assert_eq "F3: attributed finding with no map entry for its task → flag fallback (false)" "false" "$f3d_pass"

# ============================================================
# Test 8 — --category: valid category recorded on finding row
# ============================================================

printf '\n--- post-review-writer: category recorded on finding ---\n'

TMP8_DIR="${TMP_DIR}/test8"
SESSION8_DIR="${TMP8_DIR}/session"
BUILDS8_DIR="${SESSION8_DIR}/builds"
SLUG8_DIR="${TMP8_DIR}/slug-root"
mkdir -p "$SLUG8_DIR" "$BUILDS8_DIR"

cat > "${BUILDS8_DIR}/M01-T01-aaaa0008-manifest.md" <<'MD'
# Build Manifest: M01-T01-aaaa0008

## Files written
lib/target.sh
MD

cat > "${SESSION8_DIR}/features.json" <<'JSON'
{
  "tasks": [
    {
      "id": "M1.T01.target-task",
      "uuid": "aaaa0008",
      "assertionIds": ["M1.area.assertion-cat"]
    }
  ]
}
JSON

cat > "${SESSION8_DIR}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.target-task","assertion_id":"M1.area.assertion-cat","shape":"wiring","timestamp":"2026-05-30T08:00:00Z"}
JSONL

POST_REVIEW8="${SLUG8_DIR}/post-review.jsonl"

CLAUDE_PLUGIN_DATA="$SLUG8_DIR" "$WRITER" \
  --session-dir  "$SESSION8_DIR" \
  --session-id   "20260530-090000-cat00001" \
  --touched-file "lib/target.sh" \
  --severity     "minor" \
  --review-found "true" \
  --category     "architecture"

cat8_count="$(wc -l < "$POST_REVIEW8" | tr -d ' ')"
assert_eq "category: exactly one record written" "1" "$cat8_count"

cat8_category="$(jq -r '.category' "$POST_REVIEW8")"
assert_eq "category: .category == architecture" "architecture" "$cat8_category"

# All 6 prior fields must still be intact
cat8_fields="$(jq -e '.shape and .severity and (.verifier_said_PASS != null) and (.review_found != null) and .session_id and .timestamp' "$POST_REVIEW8")"
assert_eq "category: all 6 prior fields intact" "true" "$cat8_fields"

# ============================================================
# Test 9 — --category: invalid slug → exit non-zero, no record
# ============================================================

printf '\n--- post-review-writer: invalid category rejected ---\n'

TMP9_DIR="${TMP_DIR}/test9"
SESSION9_DIR="${TMP9_DIR}/session"
BUILDS9_DIR="${SESSION9_DIR}/builds"
SLUG9_DIR="${TMP9_DIR}/slug-root"
mkdir -p "$SLUG9_DIR" "$BUILDS9_DIR"

cat > "${BUILDS9_DIR}/M01-T01-aaaa0009-manifest.md" <<'MD'
# Build Manifest: M01-T01-aaaa0009

## Files written
lib/other.sh
MD

cat > "${SESSION9_DIR}/features.json" <<'JSON'
{ "tasks": [{ "id": "M1.T01.other-task", "uuid": "aaaa0009", "assertionIds": [] }] }
JSON

cat > "${SESSION9_DIR}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.other-task","assertion_id":"M1.area.x","shape":"wiring","timestamp":"2026-05-30T08:00:00Z"}
JSONL

POST_REVIEW9="${SLUG9_DIR}/post-review.jsonl"

set +e
CLAUDE_PLUGIN_DATA="$SLUG9_DIR" "$WRITER" \
  --session-dir  "$SESSION9_DIR" \
  --session-id   "20260530-091000-bogus001" \
  --touched-file "lib/other.sh" \
  --severity     "minor" \
  --review-found "true" \
  --category     "bogus" 2>/dev/null
bogus_exit=$?
set -e

assert_eq "invalid-category: exits non-zero" "1" "$bogus_exit"

bogus_written="0"
[[ -f "$POST_REVIEW9" ]] && bogus_written="$(wc -l < "$POST_REVIEW9" | tr -d ' ')"
assert_eq "invalid-category: zero records written" "0" "$bogus_written"

# ============================================================
# Test 10 — no --category → record emitted, .category null/absent,
#           all 6 prior fields intact
# ============================================================

printf '\n--- post-review-writer: no category field backward-compatible ---\n'

TMP10_DIR="${TMP_DIR}/test10"
SESSION10_DIR="${TMP10_DIR}/session"
BUILDS10_DIR="${SESSION10_DIR}/builds"
SLUG10_DIR="${TMP10_DIR}/slug-root"
mkdir -p "$SLUG10_DIR" "$BUILDS10_DIR"

cat > "${BUILDS10_DIR}/M01-T01-aaaa0010-manifest.md" <<'MD'
# Build Manifest: M01-T01-aaaa0010

## Files written
lib/nocat.sh
MD

cat > "${SESSION10_DIR}/features.json" <<'JSON'
{ "tasks": [{ "id": "M1.T01.nocat-task", "uuid": "aaaa0010", "assertionIds": ["M1.area.nc"] }] }
JSON

cat > "${SESSION10_DIR}/audit.jsonl" <<'JSONL'
{"event":"assertion_shape","task_id":"M1.T01.nocat-task","assertion_id":"M1.area.nc","shape":"data-transform","timestamp":"2026-05-30T08:00:00Z"}
JSONL

POST_REVIEW10="${SLUG10_DIR}/post-review.jsonl"

CLAUDE_PLUGIN_DATA="$SLUG10_DIR" "$WRITER" \
  --session-dir  "$SESSION10_DIR" \
  --session-id   "20260530-092000-nocat001" \
  --touched-file "lib/nocat.sh" \
  --severity     "info" \
  --review-found "true"

nocat_count="$(wc -l < "$POST_REVIEW10" | tr -d ' ')"
assert_eq "no-category: record emitted" "1" "$nocat_count"

# .category should be null or absent (jq -r returns "null" for either)
nocat_category="$(jq -r '.category // null' "$POST_REVIEW10")"
assert_eq "no-category: .category null" "null" "$nocat_category"

nocat_fields="$(jq -e '.shape and .severity and (.verifier_said_PASS != null) and (.review_found != null) and .session_id and .timestamp' "$POST_REVIEW10")"
assert_eq "no-category: all 6 prior fields intact" "true" "$nocat_fields"

report
