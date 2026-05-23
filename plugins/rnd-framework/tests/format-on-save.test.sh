#!/usr/bin/env bash
# tests/format-on-save.test.sh — Tests for hooks/format-on-save.sh
# Usage: bash tests/format-on-save.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/format-on-save.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Helper: run hook with isolated environment
# ---------------------------------------------------------------------------
# Unsets CLAUDE_PLUGIN_ROOT to prevent it from overriding CLAUDE_CONFIG_DIR
# in active_session_dir's _resolve_config_dir.
run_fmt_hook() {
  local stdin_json="$1"
  shift
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$stdin_json" | env -u CLAUDE_PLUGIN_ROOT "$@" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# ---------------------------------------------------------------------------
# Shared test environment
# ---------------------------------------------------------------------------
tmp_config="$(mktemp -d)"
tmp_base="${tmp_config}/.rnd/claude-testslug"
session_dir="${tmp_base}/sessions/20260101-120000-abcd"
mkdir -p "$session_dir"
printf '20260101-120000-abcd' > "${tmp_base}/.current-session"
mkdir -p "${tmp_config}/.rnd"
printf '%s' "$tmp_base" > "${tmp_config}/.rnd/.active-base-dir"

tmp_project="$(mktemp -d)"
cd "$tmp_project"
git init -q

# ---------------------------------------------------------------------------
# Test 1: fast-path — no active session → exit 0, no stdout
# ---------------------------------------------------------------------------
printf '%s\n' '--- format-on-save: fast-path ---'

run_fmt_hook '{"tool_input":{"file_path":"/tmp/test.ts"}}' "CLAUDE_CONFIG_DIR=/nonexistent"
assert_exit_code "no active session → exit 0" 0
assert_eq "no active session → no stdout" "" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test 2: empty file_path → exit 0, no stdout
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: empty file_path ---'

run_fmt_hook '{"tool_input":{"file_path":""}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "empty file_path → exit 0" 0
assert_eq "empty file_path → no stdout" "" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test 3: non-code file (.md) → exit 0, no stdout
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: non-code file ---'

run_fmt_hook '{"tool_input":{"file_path":"'"${tmp_project}/readme.md"'"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "non-code .md → exit 0" 0
assert_eq "non-code .md → no stdout" "" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test 4: .rnd/ artifact path → exit 0, no stdout
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: .rnd/ path ---'

run_fmt_hook '{"tool_input":{"file_path":"/Users/test/.claude-personal/.rnd/sessions/abc/plan.ts"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code ".rnd/ path → exit 0" 0
assert_eq ".rnd/ path → no stdout" "" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test 5: no formatter detected → cache {"detected":false}, exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: no formatter ---'

rm -f "${session_dir}/.formatter-cache"
run_fmt_hook '{"tool_input":{"file_path":"'"${tmp_project}/test.ts"'"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "no formatter → exit 0" 0
assert_eq "no formatter → no stdout" "" "$HOOK_STDOUT"

# Verify cache was written
if [[ -f "${session_dir}/.formatter-cache" ]]; then
  cache_content="$(cat "${session_dir}/.formatter-cache")"
  assert_eq "no formatter → cache detected:false" '{"detected":false}' "$cache_content"
else
  assert_eq "no formatter → cache file created" "exists" "missing"
fi

# ---------------------------------------------------------------------------
# Test 6: cache read on subsequent call (no re-scan)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: cache read ---'

printf '{"detected":true,"command":"echo formatted","name":"test-fmt"}' > "${session_dir}/.formatter-cache"
touch "${tmp_project}/test2.ts"
run_fmt_hook '{"tool_input":{"file_path":"'"${tmp_project}/test2.ts"'"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"

# Cache should not be overwritten
cache_after="$(cat "${session_dir}/.formatter-cache")"
assert_contains "cache not overwritten on subsequent call" '"detected":true' "$cache_after"

# ---------------------------------------------------------------------------
# Test 7: formatter execution (marker file test)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: formatter execution ---'

rm -f "${session_dir}/.formatter-cache"
marker_file="$(mktemp)"
rm -f "$marker_file"
printf '{"detected":true,"command":"touch %s #","name":"marker-fmt"}' "$marker_file" > "${session_dir}/.formatter-cache"
touch "${tmp_project}/test3.ts"
run_fmt_hook '{"tool_input":{"file_path":"'"${tmp_project}/test3.ts"'"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "formatter runs → exit 0" 0
if [[ -f "$marker_file" ]]; then
  assert_eq "formatter command executed" "executed" "executed"
else
  assert_eq "formatter command executed" "executed" "not executed"
fi
rm -f "$marker_file"

# ---------------------------------------------------------------------------
# Test 8: formatter error → exit 0 (non-blocking)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: formatter error ---'

rm -f "${session_dir}/.formatter-cache"
printf '{"detected":true,"command":"false","name":"fail-fmt"}' > "${session_dir}/.formatter-cache"
touch "${tmp_project}/test4.ts"
run_fmt_hook '{"tool_input":{"file_path":"'"${tmp_project}/test4.ts"'"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "formatter error → exit 0 (non-blocking)" 0

# ---------------------------------------------------------------------------
# Test 9: formatter detection — biome
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: biome detection ---'

rm -f "${session_dir}/.formatter-cache"
touch "${tmp_project}/biome.json"
touch "${tmp_project}/test5.ts"
run_fmt_hook '{"tool_input":{"file_path":"'"${tmp_project}/test5.ts"'"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
if [[ -f "${session_dir}/.formatter-cache" ]]; then
  cache_biome="$(cat "${session_dir}/.formatter-cache")"
  assert_contains "biome detected" '"name":"biome"' "$cache_biome"
  assert_contains "biome command" '"detected":true' "$cache_biome"
else
  assert_eq "biome → cache created" "exists" "missing"
fi
rm -f "${tmp_project}/biome.json"

# ---------------------------------------------------------------------------
# Test 10: malformed JSON input → exit 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- format-on-save: malformed input ---'

rm -f "${session_dir}/.formatter-cache"
run_fmt_hook 'not json at all' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "malformed input → exit 0" 0
assert_eq "malformed input → no stdout" "" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Test 11: command injection via file_path is not executed
# ---------------------------------------------------------------------------
# Regression: formerly `eval "$formatter_cmd" "$file_path"` would expand $(...)
# and backticks inside file_path. The array-split invocation must pass the path
# as an inert argv[1] even when it contains shell-substitution syntax.
printf '\n%s\n' '--- format-on-save: injection defense ---'

rm -f "${session_dir}/.formatter-cache"
injection_marker="$(mktemp -u)"
rm -f "$injection_marker"
# Formatter command is harmless (`true` ignores all arguments).
printf '{"detected":true,"command":"true","name":"inert-fmt"}' > "${session_dir}/.formatter-cache"
touch "${tmp_project}/ok.ts"

# file_path contains an embedded command substitution pointing at the marker.
# With the pre-fix eval, this would run `touch $injection_marker`.
injection_payload="${tmp_project}/x\$(touch ${injection_marker}).ts"
stdin_json="$(jq -nc --arg fp "$injection_payload" '{tool_input:{file_path:$fp}}')"
run_fmt_hook "$stdin_json" "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "injection: hook exits 0" 0

if [[ -e "$injection_marker" ]]; then
  assert_eq "injection defense: marker file not created" "absent" "present"
  rm -f "$injection_marker"
else
  assert_eq "injection defense: marker file not created" "absent" "absent"
fi

# ---------------------------------------------------------------------------
# Test 12: linked worktree → auto-format skipped; main checkout → runs
# ---------------------------------------------------------------------------
# Worktrees lack the project's gitignored toolchain dirs (deps/, node_modules/,
# target/, ...), so the formatter would error or diverge there. The hook must skip
# auto-format inside a linked worktree but still run in the main checkout.
printf '\n%s\n' '--- format-on-save: linked-worktree skip ---'

wt_repo="$(mktemp -d)"
( cd "$wt_repo" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )

# A formatter that, if it runs, creates the marker file.
wt_marker="$(mktemp -u)"
printf '{"detected":true,"command":"touch %s #","name":"marker-fmt"}' "$wt_marker" > "${session_dir}/.formatter-cache"

# Positive control: main checkout → formatter runs → marker created.
rm -f "$wt_marker"
touch "${wt_repo}/main.ts"
cd "$wt_repo"
run_fmt_hook '{"tool_input":{"file_path":"'"${wt_repo}/main.ts"'"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "main checkout → exit 0" 0
if [[ -e "$wt_marker" ]]; then
  assert_eq "main checkout: formatter runs" "ran" "ran"
else
  assert_eq "main checkout: formatter runs" "ran" "skipped"
fi

# Worktree: formatter must be skipped → marker NOT created.
wt_dir="$(mktemp -d)/wt"
( cd "$wt_repo" && git worktree add -q "$wt_dir" -b fmt-wt-test )
rm -f "$wt_marker"
touch "${wt_dir}/code.ts"
cd "$wt_dir"
run_fmt_hook '{"tool_input":{"file_path":"'"${wt_dir}/code.ts"'"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "worktree → exit 0" 0
if [[ -e "$wt_marker" ]]; then
  assert_eq "worktree: formatter skipped" "skipped" "ran"
  rm -f "$wt_marker"
else
  assert_eq "worktree: formatter skipped" "skipped" "skipped"
fi

cd "$tmp_project"
rm -rf "$wt_repo" "$(dirname "$wt_dir")"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$tmp_config" "$tmp_project"

report
