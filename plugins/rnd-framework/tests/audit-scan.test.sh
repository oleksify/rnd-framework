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

ensure_verifications_dir() {
  mkdir -p "${TMP_RND}/verifications"
}

clear_task_reports() {
  local task_id="$1"
  ensure_verifications_dir
  rm -f "${TMP_RND}/verifications/${task_id}-verification"*.md
}

write_verification_report() {
  local task_id="$1"
  local suffix="$2"
  local verdict="$3"
  local timestamp="$4"
  local report_path="${TMP_RND}/verifications/${task_id}-verification${suffix}.md"

  ensure_verifications_dir
  printf '# Verification Report: %s\n\n## Overall Verdict: %s\n' "$task_id" "$verdict" \
    > "$report_path"
  touch -t "$timestamp" "$report_path"
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
assert_eq "verdict_history no verifications dir prints empty output" "" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history single PASS verdict
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: single PASS ---'

clear_task_reports "T1"
printf '# Verification Report: T1\n\n## Overall Verdict: PASS\n\n## Feedback\nLooks good.\n' \
  > "${TMP_RND}/verifications/T1-verification.md"

run_scan verdict_history "T1"
assert_exit_code "single PASS exits 0" 0
assert_eq "single PASS verdict sequence" "PASS" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history deterministic ordering with mtimes and path tie-breakers
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: deterministic ordering ---'

clear_task_reports "T2"
write_verification_report "T2" "-B" "FAIL" "202601020000"
write_verification_report "T2" "-C" "PASS" "202601010000"
write_verification_report "T2" "-A" "NEEDS_ITERATION" "202601020000"

run_scan verdict_history "T2"
assert_exit_code "deterministic ordering exits 0" 0
assert_eq "deterministic ordering sorts by mtime then path" "PASS NEEDS_ITERATION FAIL" "$HOOK_STDOUT"

first_sequence="$HOOK_STDOUT"
for run_index in 1 2 3 4 5; do
  run_scan verdict_history "T2"
  assert_exit_code "deterministic ordering repeated run ${run_index} exits 0" 0
  assert_eq "deterministic ordering repeated run ${run_index}" "$first_sequence" "$HOOK_STDOUT"
done

# ---------------------------------------------------------------------------
# Test: verdict_history preserves expanded and unknown verdict tokens
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: expanded and unknown verdict tokens ---'

clear_task_reports "T3"
write_verification_report "T3" "-A" "PASS_QUALITY_NEEDS_ITERATION" "202601010000"
write_verification_report "T3" "-B" "NEEDS_ITERATION" "202601020000"
write_verification_report "T3" "-C" "EXPERIMENTAL_VERDICT" "202601030000"

run_scan verdict_history "T3"
assert_exit_code "expanded verdict sequence exits 0" 0
assert_eq \
  "expanded verdict sequence preserves full tokens" \
  "PASS_QUALITY_NEEDS_ITERATION NEEDS_ITERATION EXPERIMENTAL_VERDICT" \
  "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history PASS FAIL sequence, no flip with two terms
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: PASS FAIL sequence (no flip) ---'

clear_task_reports "T4"
write_verification_report "T4" "" "PASS" "202601010000"
write_verification_report "T4" "-B" "FAIL" "202601020000"

run_scan verdict_history "T4"
assert_exit_code "PASS FAIL sequence exits 0" 0
assert_eq "PASS FAIL sequence preserves both verdicts" "PASS FAIL" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history PASS→FAIL→PASS — FLIP_DETECTED
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: PASS FAIL PASS → FLIP_DETECTED ---'

clear_task_reports "T5"
write_verification_report "T5" "" "PASS" "202601010000"
write_verification_report "T5" "-B" "FAIL" "202601020000"
write_verification_report "T5" "-C" "PASS" "202601030000"

run_scan verdict_history "T5"
assert_exit_code "PASS FAIL PASS exits 0" 0
assert_eq "PASS FAIL PASS returns FLIP_DETECTED" "FLIP_DETECTED" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history PASS→NEEDS_ITERATION→PASS — FLIP_DETECTED
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: PASS NEEDS_ITERATION PASS → FLIP_DETECTED ---'

clear_task_reports "T6"
write_verification_report "T6" "" "PASS" "202601010000"
write_verification_report "T6" "-B" "NEEDS_ITERATION" "202601020000"
write_verification_report "T6" "-C" "PASS" "202601030000"

run_scan verdict_history "T6"
assert_exit_code "PASS NEEDS_ITERATION PASS exits 0" 0
assert_eq "PASS NEEDS_ITERATION PASS returns FLIP_DETECTED" "FLIP_DETECTED" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history PASS→PASS_QUALITY_NEEDS_ITERATION→PASS — FLIP_DETECTED
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: PASS PASS_QUALITY_NEEDS_ITERATION PASS → FLIP_DETECTED ---'

clear_task_reports "T7"
write_verification_report "T7" "" "PASS" "202601010000"
write_verification_report "T7" "-B" "PASS_QUALITY_NEEDS_ITERATION" "202601020000"
write_verification_report "T7" "-C" "PASS" "202601030000"

run_scan verdict_history "T7"
assert_exit_code "PASS PASS_QUALITY_NEEDS_ITERATION PASS exits 0" 0
assert_eq "PASS PASS_QUALITY_NEEDS_ITERATION PASS returns FLIP_DETECTED" "FLIP_DETECTED" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test: verdict_history FAIL→PASS→FAIL — FLIP_DETECTED
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-scan verdict_history: FAIL PASS FAIL → FLIP_DETECTED ---'

clear_task_reports "T8"
write_verification_report "T8" "" "FAIL" "202601010000"
write_verification_report "T8" "-B" "PASS" "202601020000"
write_verification_report "T8" "-C" "FAIL" "202601030000"

run_scan verdict_history "T8"
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
