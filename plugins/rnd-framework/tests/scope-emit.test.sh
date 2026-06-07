#!/usr/bin/env bash
# Tests for lib/scope-emit.sh
# Usage: bash tests/scope-emit.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="${SCRIPT_DIR}/../lib/scope-emit.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_SESSION="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_SESSION"
}
trap cleanup EXIT

# Run scope-emit.sh with given args and optional RND_DIR.
# Sets HOOK_EXIT, HOOK_STDOUT, HOOK_STDERR in the caller's scope.
run_emit() {
  local rnd_dir="${1:-}"
  shift
  local args=("$@")

  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  if [[ -n "$rnd_dir" ]]; then
    env -i PATH="$PATH" HOME="$HOME" RND_DIR="$rnd_dir" \
      "$EMIT" "${args[@]}" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
  else
    env -i PATH="$PATH" HOME="$HOME" \
      "$EMIT" "${args[@]}" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
  fi

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# ---------------------------------------------------------------------------
# Test 1: missing argument → exit 1
# ---------------------------------------------------------------------------
printf '%s\n' '--- scope-emit: missing argument → exit 1 ---'

run_emit "$TMP_SESSION"
assert_exit_code "no args → exit 1" 1

run_emit "$TMP_SESSION" "D1,D2"
assert_exit_code "one arg → exit 1" 1

# ---------------------------------------------------------------------------
# Test 2: missing RND_DIR → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-emit: missing RND_DIR → exit 1 ---'

run_emit "" "D1,D2" "2"
assert_exit_code "no RND_DIR → exit 1" 1

# ---------------------------------------------------------------------------
# Test 3: success — appends a jq-parseable scope_locked line to audit.jsonl
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- scope-emit: success appends scope_locked to audit.jsonl ---'

rm -f "${TMP_SESSION}/audit.jsonl"

run_emit "$TMP_SESSION" "D1,D2,D3" "3"
assert_exit_code "success → exit 0" 0

AUDIT_LINE="$(grep 'scope_locked' "${TMP_SESSION}/audit.jsonl" 2>/dev/null || true)"
assert_contains "audit.jsonl has scope_locked event" "scope_locked" "$AUDIT_LINE"

# Verify the line is valid JSON with the required fields.
PARSED_EVENT="$(printf '%s' "$AUDIT_LINE" | jq -r '.event' 2>/dev/null || true)"
assert_eq "event field is scope_locked" "scope_locked" "$PARSED_EVENT"

PARSED_N="$(printf '%s' "$AUDIT_LINE" | jq -r '.n_deliverables' 2>/dev/null || true)"
assert_eq "n_deliverables is 3" "3" "$PARSED_N"

PARSED_IDS="$(printf '%s' "$AUDIT_LINE" | jq -r '.deliverable_ids | join(",")' 2>/dev/null || true)"
assert_eq "deliverable_ids array reconstructs csv" "D1,D2,D3" "$PARSED_IDS"

# ---------------------------------------------------------------------------
report
