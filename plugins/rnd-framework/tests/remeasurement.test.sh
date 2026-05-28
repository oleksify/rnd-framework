#!/usr/bin/env bash
# Tests for lib/remeasurement.sh corpus_count and gate_met subcommands.
# Usage: bash tests/remeasurement.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${SCRIPT_DIR}/../lib/remeasurement.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# M5 ship commit SHA — confirmed reachable from HEAD.
M5_SHA="941cea0"

# M5 commit epoch: 1779963467 (2026-05-28T12:17:47 UTC)
# Timestamps BEFORE M5: 20260511 → 1778492115
# Timestamps AFTER M5:  20260529 → 1780000000+

make_session() {
  local config_dir="$1" slug="$2" branch="$3" ts_prefix="$4"
  mkdir -p "${config_dir}/.rnd/${slug}/branches/${branch}/sessions/${ts_prefix}-abcd1234"
}

# ---------------------------------------------------------------------------
# Test group: corpus_count — empty corpus
# ---------------------------------------------------------------------------
printf '%s\n' '--- corpus_count: empty corpus → 0 ---'

RND_EMPTY="${TMP_DIR}/empty"
mkdir -p "${RND_EMPTY}/.rnd/claude-130cb64f"

actual=$(CLAUDE_CONFIG_DIR="$RND_EMPTY" bash "$HARNESS" corpus_count "$M5_SHA")
assert_eq "empty corpus returns 0" "0" "$actual"

# ---------------------------------------------------------------------------
# Test group: corpus_count — 3 post + 2 pre + 1 non-dogfood
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- corpus_count: 3 post + 2 pre + 1 non-dogfood → 3 ---'

RND_MIX="${TMP_DIR}/mix"

# dogfood slug sessions (3 post-M5, 2 pre-M5)
make_session "$RND_MIX" "claude-130cb64f" "main" "20260529-100000"
make_session "$RND_MIX" "claude-130cb64f" "main" "20260529-110000"
make_session "$RND_MIX" "claude-130cb64f" "main" "20260529-120000"
make_session "$RND_MIX" "claude-130cb64f" "main" "20260511-100000"
make_session "$RND_MIX" "claude-130cb64f" "main" "20260511-110000"

# non-dogfood slug session after M5 (must NOT be counted)
make_session "$RND_MIX" "other-project-deadbeef" "main" "20260529-130000"

actual_mix=$(CLAUDE_CONFIG_DIR="$RND_MIX" bash "$HARNESS" corpus_count "$M5_SHA")
assert_eq "3 post + 2 pre + 1 non-dogfood returns 3" "3" "$actual_mix"

# ---------------------------------------------------------------------------
# Test group: corpus_count — corpus spanning branches
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- corpus_count: sessions across branches ---'

RND_BRANCH="${TMP_DIR}/branch"

# 2 sessions on main, 1 session on feature branch — all post-M5
make_session "$RND_BRANCH" "claude-130cb64f" "main"    "20260529-100000"
make_session "$RND_BRANCH" "claude-130cb64f" "main"    "20260529-110000"
make_session "$RND_BRANCH" "claude-130cb64f" "feature" "20260529-120000"

actual_branch=$(CLAUDE_CONFIG_DIR="$RND_BRANCH" bash "$HARNESS" corpus_count "$M5_SHA")
assert_eq "3 post-M5 sessions across 2 branches returns 3" "3" "$actual_branch"

# ---------------------------------------------------------------------------
# Test group: corpus_count — 12 post-commit sessions
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- corpus_count: 12 post-commit sessions → 12 ---'

RND_TWELVE="${TMP_DIR}/twelve"

for i in $(seq 1 12); do
  hour=$(printf '%02d' "$i")
  make_session "$RND_TWELVE" "claude-130cb64f" "main" "20260529-${hour}0000"
done

actual_twelve=$(CLAUDE_CONFIG_DIR="$RND_TWELVE" bash "$HARNESS" corpus_count "$M5_SHA")
assert_eq "12 post-commit sessions returns 12" "12" "$actual_twelve"

# ---------------------------------------------------------------------------
# Test group: gate_met — boundary at 9 (< 10 → exit 1)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- gate_met: 9 sessions → exit 1 ---'

RND_NINE="${TMP_DIR}/nine"

for i in $(seq 1 9); do
  hour=$(printf '%02d' "$i")
  make_session "$RND_NINE" "claude-130cb64f" "main" "20260529-${hour}0000"
done

HOOK_EXIT=0
CLAUDE_CONFIG_DIR="$RND_NINE" bash "$HARNESS" gate_met "$M5_SHA" || HOOK_EXIT=$?
assert_exit_code "9 sessions → exit 1" 1

# ---------------------------------------------------------------------------
# Test group: gate_met — boundary at 10 (= 10 → exit 0)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- gate_met: 10 sessions → exit 0 ---'

RND_TEN="${TMP_DIR}/ten"

for i in $(seq 1 10); do
  hour=$(printf '%02d' "$i")
  make_session "$RND_TEN" "claude-130cb64f" "main" "20260529-${hour}0000"
done

HOOK_EXIT=0
CLAUDE_CONFIG_DIR="$RND_TEN" bash "$HARNESS" gate_met "$M5_SHA" || HOOK_EXIT=$?
assert_exit_code "10 sessions → exit 0" 0

# ---------------------------------------------------------------------------
# Test group: gate_met — boundary at 11 (> 10 → exit 0)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- gate_met: 11 sessions → exit 0 ---'

RND_ELEVEN="${TMP_DIR}/eleven"

for i in $(seq 1 11); do
  hour=$(printf '%02d' "$i")
  make_session "$RND_ELEVEN" "claude-130cb64f" "main" "20260529-${hour}0000"
done

HOOK_EXIT=0
CLAUDE_CONFIG_DIR="$RND_ELEVEN" bash "$HARNESS" gate_met "$M5_SHA" || HOOK_EXIT=$?
assert_exit_code "11 sessions → exit 0" 0

# ---------------------------------------------------------------------------
# Test group: RND_DOGFOOD_SLUGS override
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- corpus_count: RND_DOGFOOD_SLUGS override ---'

RND_OVERRIDE="${TMP_DIR}/override"

# Default dogfood slug sessions — 2 post-M5 (should NOT be counted with override)
make_session "$RND_OVERRIDE" "claude-130cb64f"   "main" "20260529-100000"
make_session "$RND_OVERRIDE" "claude-130cb64f"   "main" "20260529-110000"

# Custom slug sessions — 1 post-M5
make_session "$RND_OVERRIDE" "myproject-aabbccdd" "main" "20260529-120000"

actual_override=$(CLAUDE_CONFIG_DIR="$RND_OVERRIDE" RND_DOGFOOD_SLUGS="myproject-aabbccdd" bash "$HARNESS" corpus_count "$M5_SHA")
assert_eq "RND_DOGFOOD_SLUGS override counts only custom slug" "1" "$actual_override"

# ---------------------------------------------------------------------------
# Test group: memo — pending stub at N=5
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- memo: pending stub when N=5 ---'

RND_MEMO_PENDING="${TMP_DIR}/memo-pending"
MEMO_PATH_PENDING="${TMP_DIR}/memo-pending-out.md"

for i in $(seq 1 5); do
  hour=$(printf '%02d' "$i")
  make_session "$RND_MEMO_PENDING" "claude-130cb64f" "main" "20260529-${hour}0000"
done

HOOK_EXIT=0
CLAUDE_CONFIG_DIR="$RND_MEMO_PENDING" bash "$HARNESS" memo "$MEMO_PATH_PENDING" "$M5_SHA" || HOOK_EXIT=$?
assert_exit_code "memo pending: exits 0" 0

pending_content="$(cat "$MEMO_PATH_PENDING")"
assert_contains "memo pending: contains 'pending — N=5'" "pending — N=5" "$pending_content"
assert_contains "memo pending: contains threshold 10" "10" "$pending_content"

# ---------------------------------------------------------------------------
# Test group: memo — populated memo at N=12
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- memo: populated memo when N=12 ---'

RND_MEMO_POP="${TMP_DIR}/memo-populated"
MEMO_PATH_POP="${TMP_DIR}/memo-populated-out.md"

for i in $(seq 1 12); do
  hour=$(printf '%02d' "$i")
  make_session "$RND_MEMO_POP" "claude-130cb64f" "main" "20260529-${hour}0000"
done

HOOK_EXIT=0
CLAUDE_CONFIG_DIR="$RND_MEMO_POP" bash "$HARNESS" memo "$MEMO_PATH_POP" "$M5_SHA" || HOOK_EXIT=$?
assert_exit_code "memo populated: exits 0" 0

pop_content="$(cat "$MEMO_PATH_POP")"
assert_contains "memo populated: has M3 baseline recall section" "## M3 baseline recall" "$pop_content"
assert_contains "memo populated: has current snapshot section" "## Current snapshot" "$pop_content"
assert_contains "memo populated: has delta vs M3 section" "## Delta vs M3" "$pop_content"
assert_contains "memo populated: has M4+M5 confound section" "## M4+M5 confound" "$pop_content"
assert_contains "memo populated: has follow-up signals section" "## Follow-up signals" "$pop_content"
assert_contains "memo populated: confound names outside-view" "outside-view" "$pop_content"
assert_contains "memo populated: confound names hide-previous-plan" "hide-previous-plan" "$pop_content"

# ---------------------------------------------------------------------------
# Test group: command layer — duckdb-absent probe exits 0 with skip message
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- command:duckdb-absent → exit 0 with skip message ---'

COMMAND_FILE="${SCRIPT_DIR}/../commands/rnd-remeasure.md"

# Extract all bash blocks from the command file and concatenate them
PROBE_SCRIPT="${TMP_DIR}/cmd-probe.sh"
awk '/^```bash$/{in_block=1; next} /^```$/{in_block=0; next} in_block{print}' \
  "$COMMAND_FILE" > "$PROBE_SCRIPT"

# Run under a PATH that has no duckdb; exit must be 0 and output must name duckdb
CMD_STDOUT="${TMP_DIR}/cmd-probe-stdout.txt"
HOOK_EXIT=0
PATH=/usr/bin:/bin bash "$PROBE_SCRIPT" > "$CMD_STDOUT" 2>&1 || HOOK_EXIT=$?
assert_exit_code "command:duckdb-absent: exits 0" 0

cmd_out="$(cat "$CMD_STDOUT")"
assert_contains "command:duckdb-absent: stdout matches skip pattern" "rnd-remeasure: duckdb not found" "$cmd_out"

# ---------------------------------------------------------------------------
# Test group: command layer — writes memo to $RND_DIR when duckdb present
# Skipped when duckdb is not on PATH (guard mirrors the command's own probe).
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- command:writes-memo → $RND_DIR/remeasurement-memo.md exists ---'

if ! command -v duckdb > /dev/null 2>&1; then
  printf '  SKIP  duckdb absent — skipping writes-memo integration test\n'
else
  # Fixture: 12 post-M5 dogfood sessions (satisfies the N>=10 gate)
  RND_CMD_FIXTURE="${TMP_DIR}/cmd-rnd"
  M5_SHA_CMD="941cea0"

  for i in $(seq 1 12); do
    hour=$(printf '%02d' "$i")
    make_session "$RND_CMD_FIXTURE" "claude-130cb64f" "main" "20260529-${hour}0000"
  done

  # The command body resolves RND_DIR via rnd-dir.sh; override by pre-setting
  # RND_DIR directly so the command writes to our fixture dir instead.
  CMD_FIXTURE_RND_DIR="${RND_CMD_FIXTURE}/session-out"
  mkdir -p "$CMD_FIXTURE_RND_DIR"

  CMD_FULL_SCRIPT="${TMP_DIR}/cmd-full.sh"
  awk '/^```bash$/{in_block=1; next} /^```$/{in_block=0; next} in_block{print}' \
    "$COMMAND_FILE" > "$CMD_FULL_SCRIPT"

  HOOK_EXIT=0
  CLAUDE_CONFIG_DIR="$RND_CMD_FIXTURE" \
    CLAUDE_PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)" \
    RND_DIR="$CMD_FIXTURE_RND_DIR" \
    M5_SHA="$M5_SHA_CMD" \
    bash "$CMD_FULL_SCRIPT" > /dev/null 2>&1 || HOOK_EXIT=$?
  assert_exit_code "command:writes-memo: exits 0" 0

  assert_eq "command:writes-memo: memo file exists and is non-empty" \
    "yes" \
    "$(test -s "${CMD_FIXTURE_RND_DIR}/remeasurement-memo.md" && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
report
