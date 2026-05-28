#!/usr/bin/env bash
# Tests for lib/replan-archive.sh
# Usage: bash tests/replan-archive.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE="${SCRIPT_DIR}/../lib/replan-archive.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SESSION_DIR="${TMP_DIR}/session"
mkdir -p "$SESSION_DIR"

CANONICAL_FILES="protocol.md validation-contract.md features.json AGENTS.md"

# Helper: create canonical artifacts in SESSION_DIR
create_canonical() {
  for f in $CANONICAL_FILES; do
    printf 'content of %s\n' "$f" > "${SESSION_DIR}/${f}"
  done
}

# ---------------------------------------------------------------------------
# Test group: first invocation → replan-1/
# ---------------------------------------------------------------------------
printf '%s\n' '--- replan-archive: first invocation produces replan-1/ ---'

create_canonical
printf 'non-canonical\n' > "${SESSION_DIR}/extra.txt"

archive_path="$("$ARCHIVE" "$SESSION_DIR")"

assert_eq "first archive path ends in replan-1" "${SESSION_DIR}/prior-plans/replan-1" "$archive_path"

for f in $CANONICAL_FILES; do
  if [[ -f "${SESSION_DIR}/prior-plans/replan-1/${f}" ]]; then
    printf '  PASS  replan-1/%s exists\n' "$f"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  replan-1/%s missing\n' "$f"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
done

# Canonical files should be gone from root
printf '\n%s\n' '--- replan-archive: canonical files removed from root ---'
for f in $CANONICAL_FILES; do
  if [[ ! -f "${SESSION_DIR}/${f}" ]]; then
    printf '  PASS  root/%s removed\n' "$f"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  root/%s still present\n' "$f"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
done

# Non-canonical file untouched
printf '\n%s\n' '--- replan-archive: non-canonical file untouched ---'
extra_present=0
[[ -f "${SESSION_DIR}/extra.txt" ]] && extra_present=1
assert_eq "extra.txt remains at root" "1" "$extra_present"

# ---------------------------------------------------------------------------
# Test group: second invocation → replan-2/
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-archive: second invocation produces replan-2/ ---'

create_canonical

archive_path2="$("$ARCHIVE" "$SESSION_DIR")"

assert_eq "second archive path ends in replan-2" "${SESSION_DIR}/prior-plans/replan-2" "$archive_path2"

assert_eq "replan-2/protocol.md exists" "1" "$([[ -f "${SESSION_DIR}/prior-plans/replan-2/protocol.md" ]] && echo 1 || echo 0)"

# replan-1 content still intact
assert_eq "replan-1/features.json still present" "1" "$([[ -f "${SESSION_DIR}/prior-plans/replan-1/features.json" ]] && echo 1 || echo 0)"

# ---------------------------------------------------------------------------
# Test group: missing argument → exit 1
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-archive: missing argument exits 1 ---'

exit_code=0
bash "$ARCHIVE" 2>/dev/null || exit_code=$?

HOOK_EXIT=$exit_code
assert_exit_code "no args → exit 1" 1

# ---------------------------------------------------------------------------
report
