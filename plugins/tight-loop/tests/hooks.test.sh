#!/usr/bin/env bash
# tests/hooks.test.sh — Tests for bash-gate.sh and prereg-gate.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(cd "${SCRIPT_DIR}/../hooks" && pwd)"

source "${SCRIPT_DIR}/test-helpers.sh"

BASH_GATE="${HOOKS_DIR}/bash-gate.sh"
PREREG_GATE="${HOOKS_DIR}/prereg-gate.sh"

# Helper: JSON for a Bash tool call
bash_input() {
  local cmd="$1"
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"agent_type":""}' "$cmd"
}

# Helper: JSON for a Write tool call
write_input() {
  local path="$1"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"},"agent_type":""}' "$path"
}

# Helper: JSON for an Edit tool call
edit_input() {
  local path="$1"
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"},"agent_type":""}' "$path"
}

# ---------------------------------------------------------------------------
# bash-gate tests
# ---------------------------------------------------------------------------

printf '\nbash-gate.sh\n'

# Criterion: blocks sed
run_hook "$BASH_GATE" "$(bash_input 'sed s/foo/bar/ file.txt')"
assert_exit_code "sed is blocked (exit 2)" 2
assert_contains "sed block message mentions Edit" "Edit" "$HOOK_STDERR"

# Criterion: allows ls -la
run_hook "$BASH_GATE" "$(bash_input 'ls -la')"
assert_exit_code "ls -la is allowed (exit 0)" 0

# Criterion: auto-allows .tight-loop/ path
FAKE_HOME="$(mktemp -d)"
TIGHT_CMD="cat ${FAKE_HOME}/.claude/.tight-loop/abc/plan.md"
run_hook "$BASH_GATE" "$(bash_input "$TIGHT_CMD")"
assert_exit_code ".tight-loop/ path is auto-allowed (exit 0)" 0
rm -rf "$FAKE_HOME"

# Criterion: does NOT contain DB guards (mix ecto, dropdb, mysqladmin, sqlite3 CLI patterns)
DB_GUARD_COUNT="$(grep -cE 'mix ecto|dropdb|mysqladmin|sqlite3[[:space:]]' "$BASH_GATE" || true)"
assert_eq "bash-gate has no DB guard patterns" "0" "$DB_GUARD_COUNT"

# Criterion: git-add .tight-loop/ is blocked
run_hook "$BASH_GATE" "$(bash_input 'git add .tight-loop/')"
assert_exit_code "git add .tight-loop/ is blocked (exit 2)" 2

# ---------------------------------------------------------------------------
# prereg-gate tests
# ---------------------------------------------------------------------------

printf '\nprereg-gate.sh\n'

# Criterion: auto-allows .tight-loop/ path regardless of prereg
FAKE_CONFIG="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$FAKE_CONFIG"
# Path must match .claude[^/]*/.*\.tight-loop/ regex (what is_plugin_artifact_path checks)
ARTIFACT_PATH="${FAKE_CONFIG}/.claude/.tight-loop/myproject-abc/prereg-task.md"

run_hook "$PREREG_GATE" "$(write_input "$ARTIFACT_PATH")"
assert_exit_code "write to .tight-loop/ is always allowed (exit 0)" 0

# Criterion: blocks Write to project file when no prereg exists
# tight_base_dir calls tight-dir.sh — we need CLAUDE_CONFIG_DIR set.
# With no prereg-*.md in base dir, it should block.
PROJECT_FILE="/tmp/fake-project/src/foo.sh"
run_hook "$PREREG_GATE" "$(write_input "$PROJECT_FILE")"
assert_exit_code "write to project file without prereg is blocked (exit 2)" 2
assert_contains "block message names prereg format" "prereg-<task-slug>.md" "$HOOK_STDERR"

# Criterion: allows Write to project file when prereg exists
BASE_DIR="$("${HOOKS_DIR}/../lib/tight-dir.sh" 2>/dev/null || true)"
if [[ -n "$BASE_DIR" ]]; then
  mkdir -p "$BASE_DIR"
  touch "${BASE_DIR}/prereg-my-task.md"

  run_hook "$PREREG_GATE" "$(write_input "$PROJECT_FILE")"
  assert_exit_code "write to project file with prereg is allowed (exit 0)" 0

  rm -f "${BASE_DIR}/prereg-my-task.md"
fi

unset CLAUDE_CONFIG_DIR

# ---------------------------------------------------------------------------
# format-on-save smoke tests
# ---------------------------------------------------------------------------

printf '\nformat-on-save.sh\n'

FORMAT_HOOK="${HOOKS_DIR}/format-on-save.sh"

# Helper: PostToolUse JSON for Write
postwrite_input() {
  local path="$1"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$path"
}

# Skips on .tight-loop/ artifact path (no output, exit 0)
FAKE_CONFIG="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$FAKE_CONFIG"
ART_PATH="${FAKE_CONFIG}/.claude/.tight-loop/abc/prereg-x.md"
run_hook "$FORMAT_HOOK" "$(postwrite_input "$ART_PATH")"
assert_exit_code "format-on-save: artifact path skipped (exit 0)" 0

# Skips on non-code file (exit 0)
NONCODE="${FAKE_CONFIG}/notes.txt"
run_hook "$FORMAT_HOOK" "$(postwrite_input "$NONCODE")"
assert_exit_code "format-on-save: non-code file skipped (exit 0)" 0

unset CLAUDE_CONFIG_DIR

# ---------------------------------------------------------------------------
# permission-denied smoke tests
# ---------------------------------------------------------------------------

printf '\npermission-denied.sh\n'

PERM_HOOK="${HOOKS_DIR}/permission-denied.sh"

# Outputs retry:true JSON, exits 0
FAKE_CONFIG="$(mktemp -d)"
export CLAUDE_CONFIG_DIR="$FAKE_CONFIG"

run_hook "$PERM_HOOK" '{"tool_name":"Bash","reason":"auto-mode-denied"}'
assert_exit_code "permission-denied: exits 0" 0
assert_contains "permission-denied: returns retry:true" '"retry":true' "$HOOK_STDOUT"
assert_contains "permission-denied: declares hookEventName" 'PermissionDenied' "$HOOK_STDOUT"

unset CLAUDE_CONFIG_DIR

# ---------------------------------------------------------------------------
# hooks.json integration: every referenced .sh file exists and is executable
# ---------------------------------------------------------------------------

printf '\nhooks.json\n'

HOOKS_JSON="${HOOKS_DIR}/hooks.json"

# Valid JSON
if jq . "$HOOKS_JSON" >/dev/null 2>&1; then
  assert_eq "hooks.json: valid JSON" "ok" "ok"
else
  assert_eq "hooks.json: valid JSON" "ok" "fail"
fi

# Every command references an existing executable .sh file under HOOKS_DIR
PLUGIN_ROOT="$(cd "${HOOKS_DIR}/.." && pwd)"
ALL_OK=1

while IFS= read -r cmd; do
  # Strip surrounding single quotes
  cmd="${cmd#\'}"
  cmd="${cmd%\'}"
  # Substitute ${CLAUDE_PLUGIN_ROOT}
  resolved="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}"

  if [[ ! -f "$resolved" ]]; then
    printf '  MISSING: %s\n' "$resolved" >&2
    ALL_OK=0
  elif [[ ! -x "$resolved" ]]; then
    printf '  NOT_EXECUTABLE: %s\n' "$resolved" >&2
    ALL_OK=0
  fi
done < <(jq -r '.. | objects | .command? // empty' "$HOOKS_JSON")

if [[ "$ALL_OK" -eq 1 ]]; then
  assert_eq "hooks.json: all referenced scripts exist and are executable" "ok" "ok"
else
  assert_eq "hooks.json: all referenced scripts exist and are executable" "ok" "fail"
fi

report
