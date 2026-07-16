#!/usr/bin/env bash
# tests/render-proof-harness.test.sh — proves the CDP render-proof harness is
# non-vacuous: it launches real headless Chrome offline, captures console
# errors and thrown exceptions, exits 0 on a clean fixture, and exits
# non-zero (naming the failure) on fixtures that throw or console.error.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CHROME_BIN="${RND_CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
HARNESS="${SCRIPT_DIR}/lib/render-check.mjs"
FIXTURES="${SCRIPT_DIR}/fixtures/render-proof"

if [[ ! -x "$CHROME_BIN" ]]; then
  printf 'SKIP: Chrome not found at %s\n' "$CHROME_BIN"
  exit 0
fi

# --- Absent-Chrome path is a loud, non-hard-failing SKIP (forced via override) ---
absent_exit=0
absent_output="$(RND_CHROME_BIN=/nonexistent/chrome node "$HARNESS" "${FIXTURES}/clean.html" 2>&1)" || absent_exit=$?
assert_eq "absent Chrome path exits 0 rather than hard-failing" "0" "$absent_exit"
assert_contains "absent Chrome path prints a loud SKIP message" "SKIP: Chrome not found at /nonexistent/chrome" "$absent_output"

# --- Non-vacuity, half 1: a genuinely clean fixture exits 0 ---
clean_exit=0
node "$HARNESS" "${FIXTURES}/clean.html" >/dev/null 2>&1 || clean_exit=$?
assert_eq "clean fixture exits 0" "0" "$clean_exit"

# --- Non-vacuity, half 2: an uncaught-exception fixture exits non-zero and names it ---
throwing_exit=0
throwing_output="$(node "$HARNESS" "${FIXTURES}/throwing.html" 2>&1)" || throwing_exit=$?
throwing_nonzero=$([[ $throwing_exit -ne 0 ]] && echo nonzero || echo zero)
assert_eq "throwing fixture exits non-zero" "nonzero" "$throwing_nonzero"
assert_contains "throwing fixture names the failure" "deliberate render-proof failure: thrown exception" "$throwing_output"

# --- A console.error fixture is captured too (the other half of the capture contract) ---
console_exit=0
console_output="$(node "$HARNESS" "${FIXTURES}/console-error.html" 2>&1)" || console_exit=$?
console_nonzero=$([[ $console_exit -ne 0 ]] && echo nonzero || echo zero)
assert_eq "console-error fixture exits non-zero" "nonzero" "$console_nonzero"
assert_contains "console-error fixture names the failure" "deliberate render-proof failure: console.error" "$console_output"

# --- --assert predicate interface: true predicate passes, false predicate fails and names itself ---
assert_pass_exit=0
node "$HARNESS" "${FIXTURES}/clean.html" \
  --assert "document.querySelector('h1').textContent === 'Clean fixture'" \
  >/dev/null 2>&1 || assert_pass_exit=$?
assert_eq "a true --assert predicate exits 0" "0" "$assert_pass_exit"

assert_fail_exit=0
assert_fail_output="$(node "$HARNESS" "${FIXTURES}/clean.html" \
  --assert "document.querySelectorAll('h1').length === 99" 2>&1)" || assert_fail_exit=$?
assert_fail_nonzero=$([[ $assert_fail_exit -ne 0 ]] && echo nonzero || echo zero)
assert_eq "a false --assert predicate exits non-zero" "nonzero" "$assert_fail_nonzero"
assert_contains "a false --assert predicate names itself" "predicate failed" "$assert_fail_output"

# --- Offline: the harness only talks to localhost CDP + file://, never a remote host ---
assert_contains "harness connects to CDP over localhost only" "127.0.0.1" "$(cat "$HARNESS")"

report
