#!/usr/bin/env bash
# Tests for lib/audit-scan.sh
# Usage: bash tests/audit-scan.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT_SCAN="${SCRIPT_DIR}/../lib/audit-scan.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_RND="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_RND"
}
trap cleanup EXIT

# Helper: run audit-scan.sh with RND_DIR set to the temp dir
run_scan() {
  local subcommand="$1"
  shift
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  RND_DIR="$TMP_RND" "$AUDIT_SCAN" "$subcommand" "$@" \
    >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# ---------------------------------------------------------------------------
# Test: --help exits 0 and prints to stdout
# ---------------------------------------------------------------------------
printf '%s\n' '--- audit-scan --help exits 0 ---'

run_scan --help
assert_exit_code "--help exits 0" 0
assert_contains "--help mentions verdict_history" "verdict_history" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: unknown subcommand exits 1, prints to stderr
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan unknown subcommand exits 1 ---'

HOOK_EXIT=0
stderr_file="$(mktemp)"
RND_DIR="$TMP_RND" "$AUDIT_SCAN" bogus_command 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stderr_file"
HOOK_STDOUT=""
assert_exit_code "unknown subcommand exits 1" 1
assert_contains "unknown subcommand prints usage to stderr" "Usage:" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test: verdict_history with no verifications dir → empty output
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: no verifications dir ---'

rm -rf "${TMP_RND}/verifications"

run_scan verdict_history "T1"
assert_exit_code "verdict_history no verifications dir exits 0" 0

# ---------------------------------------------------------------------------
# Test: verdict_history single PASS verdict
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: single PASS ---'

mkdir -p "${TMP_RND}/verifications"
printf '# Verification Report: T1\n\n## Overall Verdict: PASS\n\n## Feedback\nLooks good.\n' \
  > "${TMP_RND}/verifications/T1-verification.md"

run_scan verdict_history "T1"
assert_exit_code "single PASS exits 0" 0
assert_eq "single PASS verdict sequence" "PASS" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history PASS FAIL sequence — no flip (only 2 terms)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: PASS FAIL sequence (no flip) ---'

# Use file modification times to control order — write older file first
printf '# Verification Report: T2\n\n## Overall Verdict: PASS\n' \
  > "${TMP_RND}/verifications/T2-verification.md"
# Sleep 1 second to ensure distinct mtime
touch -t 202601010000 "${TMP_RND}/verifications/T2-verification.md"

printf '# Verification Report: T2\n\n## Overall Verdict: FAIL\n' \
  > "${TMP_RND}/verifications/T2-verification-B.md"
touch -t 202601020000 "${TMP_RND}/verifications/T2-verification-B.md"

run_scan verdict_history "T2"
assert_exit_code "PASS FAIL sequence exits 0" 0
assert_contains "PASS FAIL contains PASS" "PASS" "$HOOK_STDOUT"
assert_contains "PASS FAIL contains FAIL" "FAIL" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history PASS→FAIL→PASS — FLIP_DETECTED
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: PASS FAIL PASS → FLIP_DETECTED ---'

mkdir -p "${TMP_RND}/verifications"
rm -f "${TMP_RND}/verifications/T3"*.md

printf '# Verification Report: T3\n\n## Overall Verdict: PASS\n' \
  > "${TMP_RND}/verifications/T3-verification.md"
touch -t 202601010000 "${TMP_RND}/verifications/T3-verification.md"

printf '# Verification Report: T3\n\n## Overall Verdict: FAIL\n' \
  > "${TMP_RND}/verifications/T3-verification-B.md"
touch -t 202601020000 "${TMP_RND}/verifications/T3-verification-B.md"

printf '# Verification Report: T3\n\n## Overall Verdict: PASS\n' \
  > "${TMP_RND}/verifications/T3-verification-C.md"
touch -t 202601030000 "${TMP_RND}/verifications/T3-verification-C.md"

run_scan verdict_history "T3"
assert_exit_code "PASS FAIL PASS exits 0" 0
assert_eq "PASS FAIL PASS returns FLIP_DETECTED" "FLIP_DETECTED" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history FAIL→PASS→FAIL — FLIP_DETECTED
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: FAIL PASS FAIL → FLIP_DETECTED ---'

rm -f "${TMP_RND}/verifications/T4"*.md

printf '# Verification Report: T4\n\n## Overall Verdict: FAIL\n' \
  > "${TMP_RND}/verifications/T4-verification.md"
touch -t 202601010000 "${TMP_RND}/verifications/T4-verification.md"

printf '# Verification Report: T4\n\n## Overall Verdict: PASS\n' \
  > "${TMP_RND}/verifications/T4-verification-B.md"
touch -t 202601020000 "${TMP_RND}/verifications/T4-verification-B.md"

printf '# Verification Report: T4\n\n## Overall Verdict: FAIL\n' \
  > "${TMP_RND}/verifications/T4-verification-C.md"
touch -t 202601030000 "${TMP_RND}/verifications/T4-verification-C.md"

run_scan verdict_history "T4"
assert_exit_code "FAIL PASS FAIL exits 0" 0
assert_eq "FAIL PASS FAIL returns FLIP_DETECTED" "FLIP_DETECTED" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: RND_DIR not set → exits 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan: RND_DIR unset exits 1 ---'

HOOK_EXIT=0
stderr_file="$(mktemp)"
"$AUDIT_SCAN" verdict_history "T1" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stderr_file"
HOOK_STDOUT=""
assert_exit_code "RND_DIR unset exits 1" 1
assert_contains "RND_DIR unset stderr message" "RND_DIR" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
report
