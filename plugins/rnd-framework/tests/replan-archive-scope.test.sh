#!/usr/bin/env bash
# Tests for scope artifact handling in lib/replan-archive.sh.
# Pins the contract that scope.json and scope.md are COPIED into the
# archive directory but their originals remain frozen at session root.
#
# NOTE: These tests are EXPECTED to fail until the scope-copy behavior is
# added to lib/replan-archive.sh. They pin the contract so the build that
# adds the behavior can verify it against a clear specification.
#
# Usage: bash tests/replan-archive-scope.test.sh
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

# ---------------------------------------------------------------------------
# Fixture: canonical artifacts + scope artifacts
# ---------------------------------------------------------------------------

printf 'protocol content\n'              > "${SESSION_DIR}/protocol.md"
printf 'contract content\n'              > "${SESSION_DIR}/validation-contract.md"
printf '{"tasks":[]}\n'                  > "${SESSION_DIR}/features.json"
printf 'agents content\n'                > "${SESSION_DIR}/AGENTS.md"
printf '{"deliverables":[],"frozen":true}\n' > "${SESSION_DIR}/scope.json"
printf '# Scope\nFrozen scope prose.\n'  > "${SESSION_DIR}/scope.md"

# ---------------------------------------------------------------------------
# Run the archive — this is the action under test.
# ---------------------------------------------------------------------------

archive_path="$("$ARCHIVE" "$SESSION_DIR")"

# ---------------------------------------------------------------------------
# Test 1: originals survive at session root
# scope.json and scope.md must remain at the session root after archiving.
# ---------------------------------------------------------------------------
printf '%s\n' '--- replan-archive-scope: scope originals survive at session root ---'

HOOK_EXIT=0
[[ -f "${SESSION_DIR}/scope.json" ]] || HOOK_EXIT=1
assert_exit_code "scope.json remains at session root" 0

HOOK_EXIT=0
[[ -f "${SESSION_DIR}/scope.md" ]] || HOOK_EXIT=1
assert_exit_code "scope.md remains at session root" 0

# ---------------------------------------------------------------------------
# Test 2: copies exist in the archive directory
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-archive-scope: scope copies exist in archive dir ---'

HOOK_EXIT=0
[[ -f "${archive_path}/scope.json" ]] || HOOK_EXIT=1
assert_exit_code "scope.json copy exists in archive" 0

HOOK_EXIT=0
[[ -f "${archive_path}/scope.md" ]] || HOOK_EXIT=1
assert_exit_code "scope.md copy exists in archive" 0

# ---------------------------------------------------------------------------
# Test 3: archive copy content matches original
# The copy must be byte-identical to the original (it is a copy, not a move).
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-archive-scope: archive copy content matches original ---'

if [[ -f "${SESSION_DIR}/scope.json" && -f "${archive_path}/scope.json" ]]; then
  orig_hash="$(shasum "${SESSION_DIR}/scope.json" | awk '{print $1}')"
  copy_hash="$(shasum "${archive_path}/scope.json" | awk '{print $1}')"
  assert_eq "scope.json content identical in root and archive" "$orig_hash" "$copy_hash"
fi

if [[ -f "${SESSION_DIR}/scope.md" && -f "${archive_path}/scope.md" ]]; then
  orig_hash="$(shasum "${SESSION_DIR}/scope.md" | awk '{print $1}')"
  copy_hash="$(shasum "${archive_path}/scope.md" | awk '{print $1}')"
  assert_eq "scope.md content identical in root and archive" "$orig_hash" "$copy_hash"
fi

# ---------------------------------------------------------------------------
# Test 4: canonical artifacts are still moved (not copied) — replan-archive
# must preserve its existing behavior for the four standard files.
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- replan-archive-scope: canonical artifacts still moved to archive ---'

HOOK_EXIT=0
[[ ! -f "${SESSION_DIR}/features.json" ]] || HOOK_EXIT=1
assert_exit_code "features.json removed from session root (moved)" 0

HOOK_EXIT=0
[[ -f "${archive_path}/features.json" ]] || HOOK_EXIT=1
assert_exit_code "features.json present in archive dir" 0

# ---------------------------------------------------------------------------
report
