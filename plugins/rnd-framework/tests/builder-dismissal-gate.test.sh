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
# Test 5: Check B — problem terms in manifest without a ledger → exit 2
#
# BY DESIGN: Check B fires whenever problem terms (error, issue, broken, bug,
# failure) appear anywhere in the manifest and no found-issues ledger exists.
# This means a manifest like "Fixed a compilation error in lib.sh" will block
# without a ledger entry. This is the intended strict behavior.
# If this causes operational friction, the ledger mechanism provides the escape:
# append a found-issues entry and the hook passes.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- builder-dismissal-gate: Check B — problem term without ledger ---'

MANIFEST_C="${TMP_SESSION}/builds/T1-manifest.md"
printf '# Build Manifest: T1\n\nFixed a compilation error in lib.sh. All tests pass.\n' \
  > "$MANIFEST_C"

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "problem term without ledger → exit 2 (by design)" 2
assert_contains "stderr explains acknowledged problems" "found-issues" "$HOOK_STDERR"

rm -f "$MANIFEST_C"

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
report
