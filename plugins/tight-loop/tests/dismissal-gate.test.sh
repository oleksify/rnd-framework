#!/usr/bin/env bash
# tests/dismissal-gate.test.sh — Tests for hooks/dismissal-gate.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/dismissal-gate.sh"

source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# Set up a temporary CLAUDE_CONFIG_DIR with a tight-loop base dir.
# Sets TIGHT_BASE and exports CLAUDE_CONFIG_DIR.
setup_tight_base() {
  CLAUDE_CONFIG_DIR="$(mktemp -d)"
  TIGHT_BASE="${CLAUDE_CONFIG_DIR}/.tight-loop/test-00000000"
  mkdir -p "$TIGHT_BASE"
  export CLAUDE_CONFIG_DIR
}

cleanup_tight_base() {
  rm -rf "${CLAUDE_CONFIG_DIR:-}"
}

# Build a Stop event JSON with a string content field.
stop_json_string() {
  local content="$1"
  jq -n --arg content "$content" \
    '{"stop_reason":"end_turn","message":{"role":"assistant","content":$content}}'
}

# Build a Stop event JSON with an array content field.
stop_json_array() {
  local text="$1"
  jq -n --arg text "$text" \
    '{"stop_reason":"end_turn","message":{"role":"assistant","content":[{"type":"text","text":$text}]}}'
}

# ---------------------------------------------------------------------------
# The hook needs to know where the tight-loop base dir is.
# We point it via CLAUDE_CONFIG_DIR; tight-dir.sh uses CLAUDE_CONFIG_DIR to build
# CONFIG_DIR, then appends /.tight-loop/<slug>. For tests we bypass slug computation
# by overriding the tight_base_dir resolution via an env var.
#
# Strategy: tight_base_dir() in lib.sh calls tight-dir.sh, which calls
# plugin-dir-base.sh, which derives CONFIG_DIR from CLAUDE_CONFIG_DIR and appends
# /.tight-loop/<slug>. We can't easily control the slug, so we use a wrapper:
# dismissal-gate.sh accepts TIGHT_LOOP_BASE_DIR_OVERRIDE env var (when set,
# tight_base_dir uses that path directly). The hook uses this env var for tests.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Test: No final-report marker → exit 0, empty stderr
# ---------------------------------------------------------------------------
printf '\nTest group: no final-report marker\n'

setup_tight_base

run_hook "$HOOK" "$(stop_json_string "I have analyzed the task.")"
assert_exit_code "no final-report: exit 0" 0
assert_eq "no final-report: empty stderr" "" "$HOOK_STDERR"

cleanup_tight_base

# ---------------------------------------------------------------------------
# Test: final-report present, clean content → exit 0
# ---------------------------------------------------------------------------
printf '\nTest group: final-report, clean content\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

run_hook "$HOOK" "$(stop_json_string "Work done. <final-report>All tasks complete. Everything looks good.</final-report>")"
assert_exit_code "clean final-report: exit 0" 0
assert_eq "clean final-report: empty stderr" "" "$HOOK_STDERR"

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: dismissal phrase "pre-existing" → exit 2, stderr contains phrase
# ---------------------------------------------------------------------------
printf '\nTest group: dismissal phrase "pre-existing"\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

run_hook "$HOOK" "$(stop_json_string "<final-report>This is a pre-existing issue.</final-report>")"
assert_exit_code "pre-existing: exit 2" 2
assert_contains "pre-existing: stderr mentions phrase" "pre-existing" "$HOOK_STDERR"

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: dismissal phrase "out of scope" → exit 2
# ---------------------------------------------------------------------------
printf '\nTest group: dismissal phrase "out of scope"\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

run_hook "$HOOK" "$(stop_json_string "<final-report>That is out of scope for this task.</final-report>")"
assert_exit_code "out of scope: exit 2" 2
assert_contains "out of scope: stderr mentions phrase" "out of scope" "$HOOK_STDERR"

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: dismissal phrase "won't fix here" → exit 2
# ---------------------------------------------------------------------------
printf '\nTest group: dismissal phrase "won'\''t fix here"\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

run_hook "$HOOK" "$(stop_json_string "<final-report>I won't fix here, it's a minor nit.</final-report>")"
assert_exit_code "wont-fix-here: exit 2" 2

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: "error" term + no ledger file → exit 2, stderr mentions "found-issues"
# ---------------------------------------------------------------------------
printf '\nTest group: problem term "error", no ledger\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

run_hook "$HOOK" "$(stop_json_string "<final-report>There was an error during execution.</final-report>")"
assert_exit_code "error-no-ledger: exit 2" 2
assert_contains "error-no-ledger: stderr mentions found-issues" "found-issues" "$HOOK_STDERR"
assert_contains "error-no-ledger: stderr contains ledger path" "$TIGHT_BASE" "$HOOK_STDERR"

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: "error" term + ledger with non-empty JSON entry → exit 0
# ---------------------------------------------------------------------------
printf '\nTest group: problem term "error", ledger with entries\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

printf '%s\n' '{"issue":"test error","location":"file.sh:1","decision":"escalated","reason":"out of scope"}' \
  > "${TIGHT_BASE}/found-issues.jsonl"

run_hook "$HOOK" "$(stop_json_string "<final-report>There was an error during execution.</final-report>")"
assert_exit_code "error-with-ledger: exit 0" 0

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: "issue" term + empty ledger file (zero non-whitespace lines) → exit 2
# ---------------------------------------------------------------------------
printf '\nTest group: problem term "issue", empty ledger file\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

printf '   \n\n' > "${TIGHT_BASE}/found-issues.jsonl"

run_hook "$HOOK" "$(stop_json_string "<final-report>There is a known issue with the output.</final-report>")"
assert_exit_code "issue-empty-ledger: exit 2" 2

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: nonexistent CLAUDE_CONFIG_DIR → exit 0 (no-op, no crash)
# ---------------------------------------------------------------------------
printf '\nTest group: nonexistent CLAUDE_CONFIG_DIR\n'

export CLAUDE_CONFIG_DIR="/nonexistent/path/that/does/not/exist"
export TIGHT_LOOP_BASE_DIR_OVERRIDE=""

run_hook "$HOOK" "$(stop_json_string "<final-report>Task complete with no issues.</final-report>")"
assert_exit_code "nonexistent-config-dir: exit 0" 0

unset CLAUDE_CONFIG_DIR
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: content as array of blocks (multi-part) → properly extracts text
# ---------------------------------------------------------------------------
printf '\nTest group: multi-part content array\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

run_hook "$HOOK" "$(stop_json_array "<final-report>This is a pre-existing problem.</final-report>")"
assert_exit_code "array-content-dismissal: exit 2" 2
assert_contains "array-content-dismissal: stderr mentions phrase" "pre-existing" "$HOOK_STDERR"

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Test: content array, clean content → exit 0
# ---------------------------------------------------------------------------
printf '\nTest group: multi-part content array, clean\n'

setup_tight_base
export TIGHT_LOOP_BASE_DIR_OVERRIDE="$TIGHT_BASE"

run_hook "$HOOK" "$(stop_json_array "<final-report>All done. Everything completed successfully.</final-report>")"
assert_exit_code "array-content-clean: exit 0" 0

cleanup_tight_base
unset TIGHT_LOOP_BASE_DIR_OVERRIDE

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
report
