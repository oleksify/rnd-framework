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

# M5 ship boundary as an epoch (NOT a SHA — the harness no longer resolves git).
# Source: v5.6.0 commit 62311e9, 2026-05-28T12:17:47+02:00. Matches the harness's
# baked-in M5_EPOCH default; passed explicitly here to test the boundary value.
M5_BOUNDARY="1779963467"

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

actual=$(CLAUDE_CONFIG_DIR="$RND_EMPTY" bash "$HARNESS" corpus_count "$M5_BOUNDARY")
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

actual_mix=$(CLAUDE_CONFIG_DIR="$RND_MIX" bash "$HARNESS" corpus_count "$M5_BOUNDARY")
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

actual_branch=$(CLAUDE_CONFIG_DIR="$RND_BRANCH" bash "$HARNESS" corpus_count "$M5_BOUNDARY")
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

actual_twelve=$(CLAUDE_CONFIG_DIR="$RND_TWELVE" bash "$HARNESS" corpus_count "$M5_BOUNDARY")
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
CLAUDE_CONFIG_DIR="$RND_NINE" bash "$HARNESS" gate_met "$M5_BOUNDARY" || HOOK_EXIT=$?
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
CLAUDE_CONFIG_DIR="$RND_TEN" bash "$HARNESS" gate_met "$M5_BOUNDARY" || HOOK_EXIT=$?
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
CLAUDE_CONFIG_DIR="$RND_ELEVEN" bash "$HARNESS" gate_met "$M5_BOUNDARY" || HOOK_EXIT=$?
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

actual_override=$(CLAUDE_CONFIG_DIR="$RND_OVERRIDE" RND_DOGFOOD_SLUGS="myproject-aabbccdd" bash "$HARNESS" corpus_count "$M5_BOUNDARY")
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
CLAUDE_CONFIG_DIR="$RND_MEMO_PENDING" bash "$HARNESS" memo "$MEMO_PATH_PENDING" "$M5_BOUNDARY" || HOOK_EXIT=$?
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
CLAUDE_CONFIG_DIR="$RND_MEMO_POP" bash "$HARNESS" memo "$MEMO_PATH_POP" "$M5_BOUNDARY" || HOOK_EXIT=$?
assert_exit_code "memo populated: exits 0" 0

pop_content="$(cat "$MEMO_PATH_POP")"
assert_contains "memo populated: has M3 baseline recall section" "## M3 baseline recall" "$pop_content"
assert_contains "memo populated: has current snapshot section" "## Current snapshot" "$pop_content"
assert_contains "memo populated: has delta vs M3 section" "## Delta vs M3" "$pop_content"
assert_contains "memo populated: has M4+M5 confound section" "## M4+M5 confound" "$pop_content"
assert_contains "memo populated: has follow-up signals section" "## Follow-up signals" "$pop_content"
assert_contains "memo populated: confound names outside-view" "outside-view" "$pop_content"
assert_contains "memo populated: confound names hide-previous-plan" "hide-previous-plan" "$pop_content"
assert_contains "memo populated: states dogfood self-measurement scope" "self-measurement" "$pop_content"
assert_contains "memo populated: scope names the dogfood slug" "claude-130cb64f" "$pop_content"

# ---------------------------------------------------------------------------
# Test group: fail loud — an unresolvable (SHA-shaped) boundary
# A measurement tool must never silently count the whole corpus. The old
# 941cea0 SHA must now produce a non-zero exit and NO stdout count.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- corpus_count: SHA boundary → fail loud (exit 1, no count) ---'

RND_FAILLOUD="${TMP_DIR}/failloud"
for i in $(seq 1 3); do
  hour=$(printf '%02d' "$i")
  make_session "$RND_FAILLOUD" "claude-130cb64f" "main" "20260529-${hour}0000"
done

FAILLOUD_OUT="${TMP_DIR}/failloud-stdout.txt"
HOOK_EXIT=0
CLAUDE_CONFIG_DIR="$RND_FAILLOUD" bash "$HARNESS" corpus_count "941cea0" > "$FAILLOUD_OUT" 2>/dev/null || HOOK_EXIT=$?
assert_exit_code "SHA boundary → exit 1" 1
assert_eq "SHA boundary → no count on stdout" "" "$(cat "$FAILLOUD_OUT")"

# ---------------------------------------------------------------------------
# Test group: default boundary — omitting the arg uses the baked M5_EPOCH
# Same fixture as the mix test; with the default boundary, only the 3 post-M5
# sessions count (the 2 pre-M5 are excluded), proving the constant is 1779963467.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- corpus_count: no arg → M5 default epoch → 3 ---'

RND_DEFAULT="${TMP_DIR}/default-boundary"
make_session "$RND_DEFAULT" "claude-130cb64f" "main" "20260529-100000"
make_session "$RND_DEFAULT" "claude-130cb64f" "main" "20260529-110000"
make_session "$RND_DEFAULT" "claude-130cb64f" "main" "20260529-120000"
make_session "$RND_DEFAULT" "claude-130cb64f" "main" "20260511-100000"
make_session "$RND_DEFAULT" "claude-130cb64f" "main" "20260511-110000"

actual_default=$(CLAUDE_CONFIG_DIR="$RND_DEFAULT" bash "$HARNESS" corpus_count)
assert_eq "no-arg default boundary counts only post-M5" "3" "$actual_default"

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
    bash "$CMD_FULL_SCRIPT" > /dev/null 2>&1 || HOOK_EXIT=$?
  assert_exit_code "command:writes-memo: exits 0" 0

  assert_eq "command:writes-memo: memo file exists and is non-empty" \
    "yes" \
    "$(test -s "${CMD_FIXTURE_RND_DIR}/remeasurement-memo.md" && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# Test group: GNU date fallback — shim forces -j to fail, GNU branch must fire
#
# The shim date script exits non-zero on -j (simulating GNU coreutils) and
# translates -d "YYYY-MM-DD HH:MM:SS" to the BSD call so the assertion can
# compare shim-path epoch against native-path epoch within the same process env.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- _parse_session_epoch: GNU date fallback via -j shim ---'

SHIM_DIR="${TMP_DIR}/date-shim"
mkdir -p "$SHIM_DIR"

# Write the shim: fail on -j (GNU has no -j); translate -d to BSD equivalent.
# BSD date is the platform binary at /bin/date — never use PATH to find it here,
# because this shim IS on PATH and would cause infinite recursion.
cat > "${SHIM_DIR}/date" << 'SHIM_EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  [[ "$arg" == "-j" ]] && exit 1
done
if [[ "$1" == "-d" ]]; then
  exec /bin/date -j -f '%Y-%m-%d %H:%M:%S' "$2" "${@:3}"
fi
exec /bin/date "$@"
SHIM_EOF
chmod +x "${SHIM_DIR}/date"

# Compute the expected epoch using native BSD date (no shim on PATH here)
VALID_TS="20260529-100000"
EXPECTED_EPOCH="$(/bin/date -j -f '%Y%m%d-%H%M%S' "$VALID_TS" '+%s')"

RND_SHIM="${TMP_DIR}/gnu-shim"
make_session "$RND_SHIM" "claude-130cb64f" "main" "$VALID_TS"

# Run corpus_count with shim on PATH (boundary=1 includes all post-epoch-1 sessions)
SHIM_EPOCH=$(PATH="${SHIM_DIR}:${PATH}" CLAUDE_CONFIG_DIR="$RND_SHIM" bash "$HARNESS" corpus_count 1)
assert_eq "shim-path: nonzero epoch counted (GNU branch fired)" "1" "$SHIM_EPOCH"

# Source the harness functions (awk stops at dispatch to avoid re-entrant dispatch)
# and invoke _parse_session_epoch directly under the shim PATH.
assert_eq "shim-path: epoch equals native-BSD epoch" "$EXPECTED_EPOCH" \
  "$(PATH="${SHIM_DIR}:${PATH}" bash -c "
      source <(awk '/^subcommand=/{ exit } { print }' '${HARNESS}')
      _parse_session_epoch '${VALID_TS}-abcd1234'
    " 2>/dev/null)"

# ---------------------------------------------------------------------------
# Test group: malformed basename → 0 under shim (both BSD and GNU branches fail)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- _parse_session_epoch: malformed basename → 0 (shim active) ---'

RND_MALFORMED="${TMP_DIR}/malformed"
# Create a session dir whose name does not match YYYYMMDD-HHMMSS-XXXX
mkdir -p "${RND_MALFORMED}/.rnd/claude-130cb64f/branches/main/sessions/bad-name-00000000"

# With shim: -j fails (GNU path), then -d with "bad-name-" prefix also fails → 0
MALFORMED_COUNT=$(PATH="${SHIM_DIR}:${PATH}" CLAUDE_CONFIG_DIR="$RND_MALFORMED" bash "$HARNESS" corpus_count 1)
assert_eq "malformed basename yields 0 count (shim active)" "0" "$MALFORMED_COUNT"

# Without shim: BSD date also fails on malformed → 0
MALFORMED_COUNT_NATIVE=$(CLAUDE_CONFIG_DIR="$RND_MALFORMED" bash "$HARNESS" corpus_count 1)
assert_eq "malformed basename yields 0 count (native)" "0" "$MALFORMED_COUNT_NATIVE"

# ---------------------------------------------------------------------------
# Test group: legacy sessions layout — sessions/ sibling to branches/
# A slug dir may contain both branches/*/sessions/*/ (current layout) and
# sessions/*/ (legacy flat layout). Both must be counted.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- corpus_count: legacy sessions/ layout counted alongside branches/ ---'

RND_LEGACY="${TMP_DIR}/legacy"

# One session in the current branches layout
make_session "$RND_LEGACY" "claude-130cb64f" "main" "20260529-100000"

# One session in the legacy flat layout (sessions/ directly under slug dir)
mkdir -p "${RND_LEGACY}/.rnd/claude-130cb64f/sessions/20260529-110000-abcd1234"

# Both sessions are post-epoch-1; expect count = 2
LEGACY_COUNT=$(CLAUDE_CONFIG_DIR="$RND_LEGACY" bash "$HARNESS" corpus_count 1)
assert_eq "branches + legacy sessions both counted (total 2)" "2" "$LEGACY_COUNT"

# Confirm M5 boundary still excludes pre-M5 legacy sessions
mkdir -p "${RND_LEGACY}/.rnd/claude-130cb64f/sessions/20260511-100000-abcd1234"
LEGACY_COUNT_M5=$(CLAUDE_CONFIG_DIR="$RND_LEGACY" bash "$HARNESS" corpus_count "$M5_BOUNDARY")
assert_eq "legacy pre-M5 session excluded by boundary" "2" "$LEGACY_COUNT_M5"

# ---------------------------------------------------------------------------
report
