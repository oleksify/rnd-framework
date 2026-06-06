#!/usr/bin/env bash
# tests/bash-gate-db-guard.test.sh — Tests for the database-file-deletion guard.
# Verifies bash-gate.sh blocks real `rm` of a database file, but does NOT
# false-block benign commands that merely contain a word ending in "rm " next
# to a .db/.sqlite token (e.g. perform, confirm, transform).
# Usage: bash tests/bash-gate-db-guard.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

BASH_GATE="${SCRIPT_DIR}/../hooks/bash-gate.sh"

_make_json() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"agent_type":"rnd-builder"}' \
    "$(printf '%s' "$cmd" | jq -Rr @json | tr -d '"')"
}

printf '\n--- bash-gate: db-file deletion guard (real rm is blocked) ---\n'

run_hook "$BASH_GATE" "$(_make_json 'rm data.db')"
assert_exit_code "rm data.db is blocked (exit 2)" 2
assert_contains "rm data.db stderr names database protection" "database file" "$HOOK_STDERR"

run_hook "$BASH_GATE" "$(_make_json 'rm -f cache.sqlite')"
assert_exit_code "rm -f cache.sqlite is blocked (exit 2)" 2

run_hook "$BASH_GATE" "$(_make_json 'cd /tmp && rm app.sqlite3')"
assert_exit_code "rm after && of a .sqlite3 file is blocked (exit 2)" 2

printf '\n--- bash-gate: db guard does NOT false-block words ending in rm ---\n'

# "perform " ends in "rm " — must not trip the rm guard.
run_hook "$BASH_GATE" "$(_make_json 'perform restore from backup.db now')"
assert_exit_code "perform ... backup.db is allowed (exit 0)" 0

# "confirm " ends in "rm ".
run_hook "$BASH_GATE" "$(_make_json 'echo confirm migration of app.sqlite')"
assert_exit_code "echo confirm ... app.sqlite is allowed (exit 0)" 0

# "transform " ends in "rm ".
run_hook "$BASH_GATE" "$(_make_json 'transform schema.db into report')"
assert_exit_code "transform schema.db is allowed (exit 0)" 0

report
