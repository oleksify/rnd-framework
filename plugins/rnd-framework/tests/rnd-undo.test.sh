#!/usr/bin/env bash
# tests/rnd-undo.test.sh — Tests for lib/rnd-undo.sh
# Usage: bash tests/rnd-undo.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RND_UNDO="${SCRIPT_DIR}/../lib/rnd-undo.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Fixture: a real git repo with two tracked files
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
TMP_REPO="${TMP_DIR}/repo"
TMP_CONFIG="${TMP_DIR}/.claude"
TMP_SESSION="${TMP_CONFIG}/.rnd/test-repo/branches/main/sessions/20260101-120000-test"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Init a bare git repo for the tests
git init -q "$TMP_REPO"
git -C "$TMP_REPO" config user.email "test@example.com"
git -C "$TMP_REPO" config user.name "Test"

# Create an initial commit with one tracked file
printf 'original content\n' > "${TMP_REPO}/tracked.txt"
git -C "$TMP_REPO" add tracked.txt
git -C "$TMP_REPO" commit -q -m "initial"

# Make session directories
mkdir -p "${TMP_SESSION}/builds"

# Write a fake CLAUDE_PLUGIN_ROOT layout:
#   ${TMP_DIR}/fake-plugin/lib/rnd-dir.sh   — returns TMP_SESSION
#   ${TMP_DIR}/fake-plugin/lib/audit-event.sh — records calls to AUDIT_LOG
FAKE_LIB="${TMP_DIR}/fake-plugin/lib"
mkdir -p "$FAKE_LIB"

printf '#!/usr/bin/env bash\nprintf "%%s" "%s"\n' "$TMP_SESSION" > "${FAKE_LIB}/rnd-dir.sh"
chmod +x "${FAKE_LIB}/rnd-dir.sh"

AUDIT_LOG="${TMP_DIR}/audit-calls.log"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$AUDIT_LOG" > "${FAKE_LIB}/audit-event.sh"
chmod +x "${FAKE_LIB}/audit-event.sh"

# Override CLAUDE_PLUGIN_ROOT so rnd-undo.sh picks up fake lib scripts
export CLAUDE_PLUGIN_ROOT="${TMP_DIR}/fake-plugin"

# Helper: run rnd-undo.sh in TMP_REPO, capturing stdout/stderr/exit
run_undo() {
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  (cd "$TMP_REPO" && PATH="$PATH" CLAUDE_PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT" \
    "$RND_UNDO" "$@") \
    >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# Helper: write a manifest with two entries — one tracked, one new
write_fixture_manifest() {
  local task_id="$1"
  local new_file="$2"
  local tracked_file="$3"
  cat > "${TMP_SESSION}/builds/${task_id}-manifest.md" <<EOF
# Build Manifest: ${task_id}

## Files written
${new_file}
${tracked_file}

## Tests Written
- some test
EOF
}

# ---------------------------------------------------------------------------
# Criterion: executable
# ---------------------------------------------------------------------------
printf '\n--- rnd-undo: executable ---\n'

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if test -x "$RND_UNDO"; then
  printf '  PASS  rnd-undo.sh is executable\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  rnd-undo.sh is not executable\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Criterion: no args → non-zero + usage on stderr
# ---------------------------------------------------------------------------
printf '\n--- rnd-undo: no-args usage ---\n'

run_undo
assert_exit_code "no args → non-zero exit" 1
assert_contains "no args → usage on stderr" "Usage:" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Criterion: missing task_id → non-zero + stderr names missing path
# ---------------------------------------------------------------------------
printf '\n--- rnd-undo: missing manifest ---\n'

run_undo "T999"
assert_exit_code "T999 missing manifest → non-zero" 1
assert_contains "T999 stderr names manifest path" "T999-manifest.md" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Criterion: --dry-run prints "would" lines, no filesystem changes
# ---------------------------------------------------------------------------
printf '\n--- rnd-undo: dry-run mode ---\n'

# new_file: does NOT exist at HEAD
NEW_FILE="new-since-head.txt"
printf 'this file was created by the task\n' > "${TMP_REPO}/${NEW_FILE}"

# tracked_file: exists at HEAD, modified by task
TRACKED_FILE="tracked.txt"
printf 'modified content\n' > "${TMP_REPO}/${TRACKED_FILE}"

write_fixture_manifest "TDR" "$NEW_FILE" "$TRACKED_FILE"

run_undo "TDR" "--dry-run"
assert_exit_code "dry-run → exit 0" 0
assert_contains "dry-run prints would rm" "would rm" "$HOOK_STDOUT"
assert_contains "dry-run prints would checkout" "would checkout" "$HOOK_STDOUT"

# Verify no filesystem changes
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ -f "${TMP_REPO}/${NEW_FILE}" ]]; then
  printf '  PASS  dry-run did not delete new file\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  dry-run deleted new file (should not have)\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

TESTS_TOTAL=$((TESTS_TOTAL + 1))
current_content="$(cat "${TMP_REPO}/${TRACKED_FILE}")"
if [[ "$current_content" == "modified content" ]]; then
  printf '  PASS  dry-run did not restore tracked file\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  dry-run modified tracked file (should not have)\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Criterion: apply mode deletes new file, reverts modified file, adds audit lines
# ---------------------------------------------------------------------------
printf '\n--- rnd-undo: apply mode ---\n'

# Reset audit log
printf '' > "$AUDIT_LOG"

# The files from dry-run test are still in place — apply now
run_undo "TDR"
assert_exit_code "apply → exit 0" 0

# new_file must be gone
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ ! -f "${TMP_REPO}/${NEW_FILE}" ]]; then
  printf '  PASS  apply deleted new file\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  apply did not delete new file\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# tracked_file must match HEAD content ("original content")
TESTS_TOTAL=$((TESTS_TOTAL + 1))
head_content="$(git -C "$TMP_REPO" show HEAD:tracked.txt)"
reverted_content="$(cat "${TMP_REPO}/${TRACKED_FILE}")"
if [[ "$reverted_content" == "$head_content" ]]; then
  printf '  PASS  apply reverted tracked file to HEAD\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  apply did not revert tracked file (got: %s, expected: %s)\n' \
    "$reverted_content" "$head_content"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# audit log must have exactly 2 rnd_undo_applied entries
TESTS_TOTAL=$((TESTS_TOTAL + 1))
audit_count=0
if [[ -f "$AUDIT_LOG" ]]; then
  audit_count="$(grep -c "rnd_undo_applied" "$AUDIT_LOG" 2>/dev/null || echo "0")"
fi
if [[ "$audit_count" -eq 2 ]]; then
  printf '  PASS  apply emitted 2 audit events\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  apply emitted %s audit events (expected 2)\n' "$audit_count"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
report
