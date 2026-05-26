#!/usr/bin/env bash
# Tests for hooks/builder-dismissal-gate.sh
# Usage: bash tests/builder-dismissal-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/builder-dismissal-gate.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
mkdir -p "${TMP_SESSION}/builds"

printf '20260401-120000-abcd' > "${TMP_BASE}/.current-session"
mkdir -p "${TMP_CONFIG}/.rnd"
printf '%s' "$TMP_BASE" > "${TMP_CONFIG}/.rnd/.active-base-dir"

cleanup() {
  rm -rf "$TMP_CONFIG"
}
trap cleanup EXIT

# Helper: run the hook with CLAUDE_CONFIG_DIR pointed at the temp fixture and
# CLAUDE_PLUGIN_ROOT unset so _resolve_config_dir falls through to CLAUDE_CONFIG_DIR.
run_with_session() {
  local stdin_json="$1"
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  printf '%s' "$stdin_json" \
    | env -i PATH="$PATH" HOME="$HOME" \
        CLAUDE_CONFIG_DIR="$TMP_CONFIG" \
        "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# ---------------------------------------------------------------------------
# Test 1: non-builder agent → fast-path no-op (exit 0, empty stderr)
# ---------------------------------------------------------------------------
printf '%s\n' '--- builder-dismissal-gate: non-builder agent fast path ---'

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "rnd-verifier → exit 0" 0
assert_eq "rnd-verifier → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 2: builder + manifest with "pre-existing" → exit 2, stderr contains phrase
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: dismissal phrase blocks ---'

MANIFEST_A="${TMP_SESSION}/builds/T1-manifest.md"
printf '# Build Manifest: T1\n\nStatus: DONE\n\nThis was a pre-existing issue in the test runner.\n' \
  > "$MANIFEST_A"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "pre-existing phrase → exit 2" 2
assert_contains "stderr contains pre-existing" "pre-existing" "$HOOK_STDERR"
assert_contains "stderr contains found-issues" "found-issues" "$HOOK_STDERR"

rm -f "$MANIFEST_A"

# ---------------------------------------------------------------------------
# Test 3: builder + clean manifest → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: clean manifest passes ---'

MANIFEST_B="${TMP_SESSION}/builds/T1-manifest.md"
printf '# Build Manifest: T1\n\n## Files Modified\n- hooks/my-hook.sh\n\n## Tests Written\n- passes correctly\n' \
  > "$MANIFEST_B"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "clean manifest → exit 0" 0

rm -f "$MANIFEST_B"

# ---------------------------------------------------------------------------
# Test 4: no active session (nonexistent CLAUDE_CONFIG_DIR) → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: no active session → no-op ---'

NO_SESSION_DIR="$(mktemp -d)"
rm -rf "$NO_SESSION_DIR"  # make it nonexistent

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-builder","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$NO_SESSION_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "no active session → exit 0" 0

# ---------------------------------------------------------------------------
# Test 5: Check B — benign problem-term mentions without a ledger → exit 0
#
# "Fixed a compilation error in lib.sh" mentions "error" but it is benign:
# the term appears alongside a resolution marker ("fixed"), so Check B must
# pass it through. No ledger entry should be required.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check B — benign problem term without ledger → exit 0 ---'

MANIFEST_C="${TMP_SESSION}/builds/T1-manifest.md"
printf '# Build Manifest: T1\n\nFixed a compilation error in lib.sh. All tests pass.\n' \
  > "$MANIFEST_C"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "benign problem term without ledger → exit 0" 0

rm -f "$MANIFEST_C"

# ---------------------------------------------------------------------------
# Test 5c: Check B — genuine acknowledged-but-unfixed failure, no ledger → exit 2
#
# A manifest that acknowledges a real problem without resolving it must still
# block. "This bug is unresolved" has "bug" with no resolution markers.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check B — genuine unfixed failure, no ledger → exit 2 ---'

MANIFEST_C2="${TMP_SESSION}/builds/T1-manifest.md"
printf '# Build Manifest: T1\n\nThis bug is unresolved and will need a follow-up.\n' \
  > "$MANIFEST_C2"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "genuine unfixed failure without ledger → exit 2" 2
assert_contains "stderr explains acknowledged problems" "found-issues" "$HOOK_STDERR"

rm -f "$MANIFEST_C2"

# ---------------------------------------------------------------------------
# Test 5d: Check B — various benign mentions without ledger → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check B — various benign mentions → exit 0 ---'

MANIFEST_C3="${TMP_SESSION}/builds/T1-manifest.md"
printf '# Build Manifest: T1\n\n## Summary\nNo issues found. Added error handling. GitHub issue #42 referenced.\n' \
  > "$MANIFEST_C3"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "no issues found / error handling / GitHub issue → exit 0" 0

rm -f "$MANIFEST_C3"

# ---------------------------------------------------------------------------
# Test 5b: Check B — problem term WITH valid ledger → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check B — problem term with ledger → passes ---'

MANIFEST_D="${TMP_SESSION}/builds/T1-manifest.md"
LEDGER_D="${TMP_SESSION}/builds/T1-found-issues.jsonl"
printf '# Build Manifest: T1\n\nFixed a compilation error in lib.sh. All tests pass.\n' \
  > "$MANIFEST_D"
printf '{"issue":"compilation error in lib.sh","location":"lib.sh:42","decision":"fixed","reason":"resolved inline"}\n' \
  > "$LEDGER_D"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "problem term with ledger → exit 0" 0

rm -f "$MANIFEST_D" "$LEDGER_D"

# ---------------------------------------------------------------------------
# Test D1: Check D — DONE manifest + evidence dir exists but empty → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check D — DONE + empty evidence dir → exit 2 ---'

MANIFEST_E="${TMP_SESSION}/builds/T1-manifest.md"
EVIDENCE_DIR_E="${TMP_SESSION}/verifications/T1-evidence"
printf '# Build Manifest: T1\n\nStatus: DONE\n\nAll criteria addressed cleanly.\n' \
  > "$MANIFEST_E"
mkdir -p "$EVIDENCE_DIR_E"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "DONE + empty evidence dir → exit 2" 2
assert_contains "stderr names evidence dir" "T1-evidence" "$HOOK_STDERR"

rm -f "$MANIFEST_E"
rm -rf "$EVIDENCE_DIR_E"

# ---------------------------------------------------------------------------
# Test D2: Check D — DONE manifest + evidence dir with VAL-*.txt → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check D — DONE + evidence VAL file → exit 0 ---'

MANIFEST_F="${TMP_SESSION}/builds/T1-manifest.md"
EVIDENCE_DIR_F="${TMP_SESSION}/verifications/T1-evidence"
printf '# Build Manifest: T1\n\nStatus: DONE\n\nAll criteria addressed cleanly.\n' \
  > "$MANIFEST_F"
mkdir -p "$EVIDENCE_DIR_F"
printf 'evidence content\n' > "${EVIDENCE_DIR_F}/VAL-001.txt"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "DONE + evidence VAL file → exit 0" 0

rm -f "$MANIFEST_F"
rm -rf "$EVIDENCE_DIR_F"

# ---------------------------------------------------------------------------
# Test D3: Check D — DONE manifest + no evidence dir → exit 0 (first build)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check D — DONE + no evidence dir → exit 0 (first build) ---'

MANIFEST_G="${TMP_SESSION}/builds/T1-manifest.md"
printf '# Build Manifest: T1\n\nStatus: DONE\n\nAll criteria addressed cleanly.\n' \
  > "$MANIFEST_G"
# Deliberately do NOT create the evidence dir — simulates a first build.
rm -rf "${TMP_SESSION}/verifications/T1-evidence"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "DONE + no evidence dir → exit 0" 0

rm -f "$MANIFEST_G"

# ---------------------------------------------------------------------------
# Test D4: Check D — non-DONE manifest + empty evidence dir → exit 0 (gate skipped)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check D — non-DONE manifest → gate skipped ---'

MANIFEST_H="${TMP_SESSION}/builds/T1-manifest.md"
EVIDENCE_DIR_H="${TMP_SESSION}/verifications/T1-evidence"
printf '# Build Manifest: T1\n\nStatus: NEEDS_CONTEXT\n\nAwaiting clarification.\n' \
  > "$MANIFEST_H"
mkdir -p "$EVIDENCE_DIR_H"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "non-DONE manifest → exit 0" 0

rm -f "$MANIFEST_H"
rm -rf "$EVIDENCE_DIR_H"

# ---------------------------------------------------------------------------
# Test D5: Check D — DONE_WITH_CONCERNS + empty evidence dir → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check D — DONE_WITH_CONCERNS + empty evidence dir → exit 2 ---'

MANIFEST_I="${TMP_SESSION}/builds/T1-manifest.md"
EVIDENCE_DIR_I="${TMP_SESSION}/verifications/T1-evidence"
printf '# Build Manifest: T1\n\nStatus: DONE_WITH_CONCERNS\n\nAll criteria addressed but with one concern noted.\n' \
  > "$MANIFEST_I"
mkdir -p "$EVIDENCE_DIR_I"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "DONE_WITH_CONCERNS + empty evidence dir → exit 2" 2
assert_contains "stderr names evidence dir for DONE_WITH_CONCERNS" "T1-evidence" "$HOOK_STDERR"

rm -f "$MANIFEST_I"
rm -rf "$EVIDENCE_DIR_I"

# ---------------------------------------------------------------------------
# Test D6: Check D — DONE + evidence dir with only a 0-byte VAL file → exit 2
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check D — DONE + 0-byte VAL file → exit 2 ---'

MANIFEST_J="${TMP_SESSION}/builds/T1-manifest.md"
EVIDENCE_DIR_J="${TMP_SESSION}/verifications/T1-evidence"
printf '# Build Manifest: T1\n\nStatus: DONE\n\nAll criteria addressed cleanly.\n' \
  > "$MANIFEST_J"
mkdir -p "$EVIDENCE_DIR_J"
touch "${EVIDENCE_DIR_J}/VAL-bypass.txt"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "DONE + 0-byte VAL file → exit 2" 2
assert_contains "stderr explains empty-files-do-not-satisfy" "non-empty" "$HOOK_STDERR"

rm -f "$MANIFEST_J"
rm -rf "$EVIDENCE_DIR_J"

# ---------------------------------------------------------------------------
report
