#!/usr/bin/env bash
# Tests for per-task_type threshold logic in hooks/cleanup-bloat-gate.sh.
# Usage: bash tests/cleanup-bloat-gate-task-type.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/cleanup-bloat-gate.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture setup — mirrors cleanup-bloat-gate.test.sh conventions
# ---------------------------------------------------------------------------

TMP_CONFIG="$(mktemp -d)"
TMP_BASE="${TMP_CONFIG}/.rnd/test-project"
TMP_SESSION="${TMP_BASE}/sessions/20260518-120000-aa11"
TMP_AUDIT="${TMP_SESSION}/audit.jsonl"

mkdir -p "${TMP_SESSION}/cleanup"

printf '20260518-120000-aa11' > "${TMP_BASE}/.current-session"
mkdir -p "${TMP_CONFIG}/.rnd"
printf '%s' "$TMP_BASE" > "${TMP_CONFIG}/.rnd/.active-base-dir"

cleanup() {
  rm -rf "$TMP_CONFIG"
}
trap cleanup EXIT

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

audit_event_count() {
  local tool="$1"
  if [[ ! -f "$TMP_AUDIT" ]]; then
    printf '0'
    return
  fi
  grep -c "\"tool\":\"${tool}\"" "$TMP_AUDIT" 2>/dev/null || printf '0'
}

reset_audit() {
  rm -f "$TMP_AUDIT"
}

AGENT_JSON='{"agent_type":"rnd-cleanup","stop_reason":"end_turn"}'

# ---------------------------------------------------------------------------
# docs: 0% deletion ratio — gate must NOT fire regardless of ratio
# ---------------------------------------------------------------------------
printf '%s\n' '--- task_type=docs: 0%% deletion → gate skipped (no advisory) ---'

REPORT="${TMP_SESSION}/cleanup/T20-cleanup-report.md"
printf '# Cleanup Report: T20\ntask_type: docs\nlines_removed: 0\ntotal_touched: 500\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT"

reset_audit
run_with_session "$AGENT_JSON"
assert_exit_code "docs 0%% → exit 0" 0
assert_eq "docs 0%% → no advisory in stderr" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "docs 0%% → no audit event" "0" "$count"

rm -f "$REPORT"

# ---------------------------------------------------------------------------
# docs: even a very low (non-zero) ratio must still not fire
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- task_type=docs: 1%% deletion → gate skipped (no advisory) ---'

REPORT="${TMP_SESSION}/cleanup/T21-cleanup-report.md"
printf '# Cleanup Report: T21\ntask_type: docs\nlines_removed: 1\ntotal_touched: 200\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT"

reset_audit
run_with_session "$AGENT_JSON"
assert_exit_code "docs 1%% → exit 0" 0
assert_eq "docs 1%% → no advisory" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "docs 1%% → no audit event" "0" "$count"

rm -f "$REPORT"

# ---------------------------------------------------------------------------
# config: 3% → DOES fire (below 5% threshold)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- task_type=config: 3%% deletion → gate fires ---'

REPORT="${TMP_SESSION}/cleanup/T22-cleanup-report.md"
printf '# Cleanup Report: T22\ntask_type: config\nlines_removed: 3\ntotal_touched: 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT"

reset_audit
run_with_session "$AGENT_JSON"
assert_exit_code "config 3%% → exit 0 (advisory only)" 0
assert_contains "config 3%% → advisory in stderr" "cleanup-bloat-gate" "$HOOK_STDERR"
assert_contains "config 3%% → task_id in stderr" "T22" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "config 3%% → audit event emitted" "1" "$count"

rm -f "$REPORT"

# ---------------------------------------------------------------------------
# config: 6% → does NOT fire (at or above 5% threshold)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- task_type=config: 6%% deletion → gate does NOT fire ---'

REPORT="${TMP_SESSION}/cleanup/T23-cleanup-report.md"
printf '# Cleanup Report: T23\ntask_type: config\nlines_removed: 6\ntotal_touched: 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT"

reset_audit
run_with_session "$AGENT_JSON"
assert_exit_code "config 6%% → exit 0" 0
assert_eq "config 6%% → no advisory" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "config 6%% → no audit event" "0" "$count"

rm -f "$REPORT"

# ---------------------------------------------------------------------------
# refactor: 18% → DOES fire (below 20% threshold)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- task_type=refactor: 18%% deletion → gate fires ---'

REPORT="${TMP_SESSION}/cleanup/T24-cleanup-report.md"
printf '# Cleanup Report: T24\ntask_type: refactor\nlines_removed: 18\ntotal_touched: 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT"

reset_audit
run_with_session "$AGENT_JSON"
assert_exit_code "refactor 18%% → exit 0 (advisory only)" 0
assert_contains "refactor 18%% → advisory in stderr" "cleanup-bloat-gate" "$HOOK_STDERR"
assert_contains "refactor 18%% → task_id in stderr" "T24" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "refactor 18%% → audit event emitted" "1" "$count"

rm -f "$REPORT"

# ---------------------------------------------------------------------------
# refactor: 22% → does NOT fire (at or above 20% threshold)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- task_type=refactor: 22%% deletion → gate does NOT fire ---'

REPORT="${TMP_SESSION}/cleanup/T25-cleanup-report.md"
printf '# Cleanup Report: T25\ntask_type: refactor\nlines_removed: 22\ntotal_touched: 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT"

reset_audit
run_with_session "$AGENT_JSON"
assert_exit_code "refactor 22%% → exit 0" 0
assert_eq "refactor 22%% → no advisory" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "refactor 22%% → no audit event" "0" "$count"

rm -f "$REPORT"

# ---------------------------------------------------------------------------
# absent task_type: → falls back to 15% default (backward compat)
# 10% should fire; 20% should not
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- absent task_type: 10%% → falls back to 15%% default → fires ---'

REPORT="${TMP_SESSION}/cleanup/T26-cleanup-report.md"
printf '# Cleanup Report: T26\nlines_removed: 10\ntotal_touched: 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT"

reset_audit
run_with_session "$AGENT_JSON"
assert_exit_code "absent task_type 10%% → exit 0 (advisory)" 0
assert_contains "absent task_type 10%% → advisory in stderr" "cleanup-bloat-gate" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "absent task_type 10%% → audit event emitted" "1" "$count"

rm -f "$REPORT"

printf '\n%s\n' '--- absent task_type: 20%% → falls back to 15%% default → does NOT fire ---'

REPORT="${TMP_SESSION}/cleanup/T27-cleanup-report.md"
printf '# Cleanup Report: T27\nlines_removed: 20\ntotal_touched: 100\n\n## Outcome\ncleanup applied\n' \
  > "$REPORT"

reset_audit
run_with_session "$AGENT_JSON"
assert_exit_code "absent task_type 20%% → exit 0" 0
assert_eq "absent task_type 20%% → no advisory" "" "$HOOK_STDERR"

count="$(audit_event_count "bloat_aversion_underperform")"
assert_eq "absent task_type 20%% → no audit event" "0" "$count"

rm -f "$REPORT"

# ---------------------------------------------------------------------------
report
