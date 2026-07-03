#!/usr/bin/env bash
# Tests for hooks/cleanup-bloat-gate.sh
# Usage: bash tests/cleanup-bloat-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/cleanup-bloat-gate.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260401-120000-abcd"
TMP_AUDIT="${TMP_SESSION}/audit.jsonl"

mkdir -p "${TMP_SESSION}/cleanup"

printf '20260401-120000-abcd' > "${TMP_BASE}/.current-session"
mkdir -p "${TMP_CONFIG}/.rnd"
printf '%s' "$TMP_BASE" > "${TMP_CONFIG}/.rnd/.active-base-dir"

cleanup() {
  rm -rf "$TMP_CONFIG"
}
trap cleanup EXIT

# Helper: run the hook with CLAUDE_CONFIG_DIR pointed at the temp fixture.
# Sets HOOK_EXIT, HOOK_STDOUT, HOOK_STDERR in the caller's scope.
run_with_session() {
  local stdin_json="$1"
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  printf '%s' "$stdin_json" \
    | env -i PATH="$PATH" HOME="$HOME" \
        CLAUDE_CONFIG_DIR="$TMP_CONFIG" \
        RND_DIR="$TMP_SESSION" \
        "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# Helper: count gate_fired events in audit.jsonl for a specific tool.
audit_event_count() {
  local tool="$1"
  if [[ ! -f "$TMP_AUDIT" ]]; then
    printf '0'
    return
  fi
  grep -c "\"tool\":\"${tool}\"" "$TMP_AUDIT" 2>/dev/null || printf '0'
}

# Reset audit log between tests.
reset_audit() {
  rm -f "$TMP_AUDIT"
}

# ---------------------------------------------------------------------------
# Test 1: non-cleanup agent → fast-path exit 0
# ---------------------------------------------------------------------------
printf '%s\n' '--- cleanup-bloat-gate: non-cleanup agent fast path ---'

run_with_session '{"agent_type":"rnd-builder","stop_reason":"end_turn"}'
assert_exit_code "rnd-builder → exit 0" 0
assert_eq "rnd-builder → empty stderr" "" "$HOOK_STDERR"

run_with_session '{"agent_type":"rnd-verifier","stop_reason":"end_turn"}'
assert_exit_code "rnd-verifier → exit 0" 0
assert_eq "rnd-verifier → empty stderr" "" "$HOOK_STDERR"

run_with_session '{"agent_type":"","stop_reason":"end_turn"}'
assert_exit_code "empty agent_type → exit 0" 0

# ---------------------------------------------------------------------------
# Test 2: rnd-cleanup with no cleanup reports → exit 0 silently
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- cleanup-bloat-gate: no cleanup reports → silent exit 0 ---'

rm -f "${TMP_SESSION}/cleanup/"T*-cleanup-report.md

reset_audit
run_with_session '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'
assert_exit_code "no reports → exit 0" 0
assert_eq "no reports → empty stderr" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "no reports → no audit event" "0" "$count"

# ---------------------------------------------------------------------------
# Test 3: lines_removed + total_touched giving ratio <15% → advisory + event
# lines_removed: 50, total_touched: 600 → 8% (below threshold)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- cleanup-bloat-gate: lines_removed ratio <15%% → advisory + audit event ---'

REPORT_A="${TMP_SESSION}/cleanup/T5-cleanup-report.md"
printf '# Cleanup Report: T5\nlines_removed: 50\ntotal_touched: 600\n\n## Detection Results\n\n### Dead Functions\n- removed dead_fn\n\n## Mutations Applied\n- src/lib.sh\n\n## Verification Result\nPASS\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT_A"

reset_audit
run_with_session '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'
assert_exit_code "lines_removed ratio <15%% → exit 0 (advisory only)" 0
assert_contains "stderr contains cleanup-bloat-gate" "cleanup-bloat-gate" "$HOOK_STDERR"
assert_contains "stderr contains task_id" "T5" "$HOOK_STDERR"
assert_contains "stderr contains deletion ratio" "8%" "$HOOK_STDERR"
assert_contains "stderr mentions advisory floor" "15%" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "lines_removed ratio <15%% → audit event emitted" "1" "$count"

rm -f "$REPORT_A"

# ---------------------------------------------------------------------------
# Test 4: Deletion ratio: 50 / 100 → 50% → exit 0 silently (no advisory)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- cleanup-bloat-gate: Deletion ratio 50%% → silent exit 0 ---'

REPORT_B="${TMP_SESSION}/cleanup/T6-cleanup-report.md"
printf '# Cleanup Report: T6\n\n## Detection Results\n\n### Dead Functions\n- removed helper\n\n## Mutations Applied\n- (none)\n\n## Verification Result\nPASS\n\nDeletion ratio: 50 / 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT_B"

reset_audit
run_with_session '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'
assert_exit_code "50%% ratio → exit 0" 0
assert_eq "50%% ratio → empty stderr" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "50%% ratio → no audit event" "0" "$count"

rm -f "$REPORT_B"

# ---------------------------------------------------------------------------
# Test 5: Deletion ratio: 1 / 100 → 1% → advisory + event + exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- cleanup-bloat-gate: Deletion ratio 1%% → advisory + audit event ---'

REPORT_C="${TMP_SESSION}/cleanup/T7-cleanup-report.md"
printf '# Cleanup Report: T7\n\n## Detection Results\n\n### Dead Functions\n- (none)\n\n## Mutations Applied\n- (none)\n\n## Verification Result\nPASS\n\nDeletion ratio: 1 / 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT_C"

reset_audit
run_with_session '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'
assert_exit_code "1%% ratio → exit 0" 0
assert_contains "1%% ratio → stderr advisory" "cleanup-bloat-gate" "$HOOK_STDERR"
assert_contains "1%% ratio → stderr mentions T7" "T7" "$HOOK_STDERR"
assert_contains "1%% ratio → shows 1%%" "1%" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "1%% ratio → audit event emitted" "1" "$count"

rm -f "$REPORT_C"

# ---------------------------------------------------------------------------
# Test 6: no ratio fields at all → exit 0 silently, no audit event
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- cleanup-bloat-gate: no ratio fields → silent exit 0, no event ---'

REPORT_D="${TMP_SESSION}/cleanup/T8-cleanup-report.md"
printf '# Cleanup Report: T8\n\n## Detection Results\n\n### Dead Functions\n- (none)\n\n## Mutations Applied\n- (none)\n\n## Verification Result\nskipped (no findings)\n\n## Outcome\ncleanup skipped (no findings)\n' \
  > "$REPORT_D"

reset_audit
run_with_session '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'
assert_exit_code "no ratio fields → exit 0" 0
assert_eq "no ratio fields → empty stderr" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "no ratio fields → no audit event" "0" "$count"

rm -f "$REPORT_D"

# ---------------------------------------------------------------------------
# Test 7: Deletion ratio exactly 15% → exit 0 silently (boundary — not below)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- cleanup-bloat-gate: Deletion ratio exactly 15%% → silent exit 0 ---'

REPORT_E="${TMP_SESSION}/cleanup/T9-cleanup-report.md"
printf '# Cleanup Report: T9\n\nDeletion ratio: 15 / 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT_E"

reset_audit
run_with_session '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'
assert_exit_code "15%% boundary → exit 0" 0
assert_eq "15%% boundary → empty stderr" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "15%% boundary → no audit event" "0" "$count"

rm -f "$REPORT_E"

# ---------------------------------------------------------------------------
# Test 8: no active session → exit 0 silently
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- cleanup-bloat-gate: no active session → silent exit 0 ---'

NO_SESSION_DIR="$(mktemp -d)"
rm -rf "$NO_SESSION_DIR"

HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$NO_SESSION_DIR" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$stdout_file")"; HOOK_STDERR="$(cat "$stderr_file")"
rm -f "$stdout_file" "$stderr_file"

assert_exit_code "no active session → exit 0" 0
assert_eq "no active session → empty stderr" "" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Test 9: RND_DIR UNSET in env (the real hook condition) — the audit event must
# still fire, resolved via session_dir. Revert-proof: the old ${RND_DIR:-} guard
# never fired the event because this hook never sets RND_DIR.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- cleanup-bloat-gate: RND_DIR unset → audit event still emitted ---'

REPORT_F="${TMP_SESSION}/cleanup/T10-cleanup-report.md"
printf '# Cleanup Report: T10\n\nDeletion ratio: 1 / 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT_F"

reset_audit
HOOK_EXIT=0
stdout_file="$(mktemp)"; stderr_file="$(mktemp)"
printf '%s' '{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}' \
  | env -i PATH="$PATH" HOME="$HOME" \
      CLAUDE_CONFIG_DIR="$TMP_CONFIG" \
      "$HOOK" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?
HOOK_STDERR="$(cat "$stderr_file")"; rm -f "$stdout_file" "$stderr_file"

assert_exit_code "RND_DIR unset → exit 0" 0
count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "RND_DIR unset → audit event STILL emitted (via session_dir)" "1" "$count"

rm -f "$REPORT_F"

# ---------------------------------------------------------------------------
report
