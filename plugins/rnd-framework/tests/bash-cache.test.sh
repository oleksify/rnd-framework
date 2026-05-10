#!/usr/bin/env bash
# tests/bash-cache.test.sh — Tests for the Bash output cache writer
# (post-dispatch.sh) and cache-hit advisory (bash-gate.sh).
# Usage: bash tests/bash-cache.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POST_HOOK="${SCRIPT_DIR}/../hooks/post-dispatch.sh"
PRE_HOOK="${SCRIPT_DIR}/../hooks/bash-gate.sh"
LIB_SH="${SCRIPT_DIR}/../hooks/lib.sh"
RND_DIR_SH="${SCRIPT_DIR}/../lib/rnd-dir.sh"

PASS=0
FAIL=0

pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

run_hook() {
  local hook="$1" stdin_json="$2" env_vars="${3:-}"
  HOOK_STDOUT=""
  HOOK_STDERR=""
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"

  if [[ -n "$env_vars" ]]; then
    printf '%s' "$stdin_json" | env $env_vars "$hook" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  else
    printf '%s' "$stdin_json" | "$hook" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  fi

  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

assert_exit() {
  local name="$1" expected="$2"
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then pass "$name"; else fail "$name" "expected exit $expected, got $HOOK_EXIT"; fi
}

assert_file_exists() {
  local name="$1" path="$2"
  if [[ -f "$path" ]]; then pass "$name"; else fail "$name" "expected file at $path"; fi
}

assert_file_missing() {
  local name="$1" path="$2"
  if [[ ! -f "$path" ]]; then pass "$name"; else fail "$name" "expected no file at $path"; fi
}

assert_file_contains() {
  local name="$1" path="$2" needle="$3"
  if [[ -f "$path" ]] && grep -q -- "$needle" "$path" 2>/dev/null; then
    pass "$name"
  else
    fail "$name" "expected '$needle' in $path"
  fi
}

assert_stdout_contains() {
  local name="$1" needle="$2"
  if [[ "$HOOK_STDOUT" == *"$needle"* ]]; then pass "$name"; else fail "$name" "expected stdout to contain '$needle', got: '$HOOK_STDOUT'"; fi
}

assert_stdout_empty() {
  local name="$1"
  if [[ -z "$HOOK_STDOUT" ]]; then pass "$name"; else fail "$name" "expected empty stdout, got: '$HOOK_STDOUT'"; fi
}

assert_no_cache_advisory() {
  local name="$1"
  if [[ "$HOOK_STDOUT" != *"Bash output cache"* ]]; then
    pass "$name"
  else
    fail "$name" "expected no cache advisory, got: '$HOOK_STDOUT'"
  fi
}

# ---------------------------------------------------------------------------
# Hash stability — sourced helpers
# ---------------------------------------------------------------------------

# shellcheck source=../hooks/lib.sh
source "$LIB_SH"

h1="$(cmd_hash 'mix test test/foo.exs')"
h2="$(cmd_hash '  mix   test  test/foo.exs  ')"
h3="$(cmd_hash $'mix\ttest test/foo.exs')"
h4="$(cmd_hash 'mix test test/bar.exs')"

if [[ -n "$h1" && "$h1" == "$h2" && "$h1" == "$h3" ]]; then
  pass "cmd_hash stable across whitespace variation"
else
  fail "cmd_hash stable across whitespace variation" "h1=$h1 h2=$h2 h3=$h3"
fi

if [[ -n "$h4" && "$h1" != "$h4" ]]; then
  pass "cmd_hash distinguishes different commands"
else
  fail "cmd_hash distinguishes different commands" "h1=$h1 h4=$h4"
fi

if [[ "${#h1}" -eq 16 ]]; then
  pass "cmd_hash returns 16-char hex prefix"
else
  fail "cmd_hash returns 16-char hex prefix" "got ${#h1} chars"
fi

empty_hash="$(cmd_hash '')"
if [[ -z "$empty_hash" ]]; then
  pass "cmd_hash on empty input returns empty"
else
  fail "cmd_hash on empty input returns empty" "got '$empty_hash'"
fi

# ---------------------------------------------------------------------------
# Writer: no active session → no cache files written
# ---------------------------------------------------------------------------

run_hook "$POST_HOOK" '{"tool_name":"Bash","tool_input":{"command":"echo hi"},"stdout":"hi"}'
assert_exit "writer no-session → exits 0" 0

# ---------------------------------------------------------------------------
# Set up an active session for the remaining tests
# ---------------------------------------------------------------------------

tmp_config="$(mktemp -d)"
base_dir="$(CLAUDE_CONFIG_DIR="$tmp_config" "$RND_DIR_SH" --base 2>/dev/null || true)"

if [[ -z "$base_dir" ]]; then
  fail "session bootstrap" "rnd-dir.sh --base failed; skipping session-dependent tests"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  rm -rf "$tmp_config"
  [[ "$FAIL" -eq 0 ]]
  exit
fi

session_id="20260101-120000-abcd"
session_dir="${base_dir}/sessions/${session_id}"
mkdir -p "$session_dir"
printf '%s' "$session_id" > "${base_dir}/.current-session"

cache_dir="${session_dir}/.bash-cache"

# ---------------------------------------------------------------------------
# Writer: stdout present → cache file + meta written
# ---------------------------------------------------------------------------

big_stdout="$(seq 1 20 | sed 's/^/line /')"
write_json="$(jq -cn --arg s "$big_stdout" '{tool_name:"Bash",tool_input:{command:"mix test test/foo.exs"},stdout:$s}')"
run_hook "$POST_HOOK" "$write_json" "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit "writer with session+stdout → exits 0" 0

key="$(cmd_hash 'mix test test/foo.exs')"
assert_file_exists "writer creates cache file" "${cache_dir}/${key}.txt"
assert_file_exists "writer creates meta file" "${cache_dir}/${key}.meta.json"
assert_file_contains "cache file holds stdout" "${cache_dir}/${key}.txt" "line 15"
assert_file_contains "meta records the command" "${cache_dir}/${key}.meta.json" '"mix test test/foo.exs"'
assert_file_contains "meta records the hash" "${cache_dir}/${key}.meta.json" "\"$key\""

# ---------------------------------------------------------------------------
# Writer: empty stdout AND empty stderr → no cache file
# ---------------------------------------------------------------------------

run_hook "$POST_HOOK" '{"tool_name":"Bash","tool_input":{"command":"true"},"stdout":"","stderr":""}' "CLAUDE_CONFIG_DIR=${tmp_config}"
empty_key="$(cmd_hash 'true')"
assert_file_missing "writer skips empty output" "${cache_dir}/${empty_key}.txt"

# ---------------------------------------------------------------------------
# Writer: stderr present, stdout empty → cache file written
# ---------------------------------------------------------------------------

stderr_json="$(jq -cn '{tool_name:"Bash",tool_input:{command:"some-failing-cmd"},stdout:"",stderr:"compile error\nat line 5"}')"
run_hook "$POST_HOOK" "$stderr_json" "CLAUDE_CONFIG_DIR=${tmp_config}"
stderr_key="$(cmd_hash 'some-failing-cmd')"
assert_file_exists "writer caches stderr-only output" "${cache_dir}/${stderr_key}.txt"
assert_file_contains "cache file holds stderr" "${cache_dir}/${stderr_key}.txt" "compile error"

# ---------------------------------------------------------------------------
# Advisory: cache hit on the same command → emits advisory
# ---------------------------------------------------------------------------

advisory_input='{"tool_name":"Bash","tool_input":{"command":"mix test test/foo.exs"}}'
run_hook "$PRE_HOOK" "$advisory_input" "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit "advisory on cache hit → exits 0" 0
assert_stdout_contains "advisory mentions cache" "Bash output cache"
assert_stdout_contains "advisory cites cached path" "${key}.txt"
assert_stdout_contains "advisory mentions Read + Grep" "Read + Grep"

# ---------------------------------------------------------------------------
# Advisory: cache miss on different command → no advisory
# ---------------------------------------------------------------------------

run_hook "$PRE_HOOK" '{"tool_name":"Bash","tool_input":{"command":"echo never-cached-cmd"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit "advisory on cache miss → exits 0" 0
assert_no_cache_advisory "no cache advisory when command not cached"

# ---------------------------------------------------------------------------
# Advisory: hash stability — re-run with extra whitespace still hits cache
# ---------------------------------------------------------------------------

run_hook "$PRE_HOOK" '{"tool_name":"Bash","tool_input":{"command":"  mix   test   test/foo.exs  "}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_stdout_contains "advisory fires on whitespace-equivalent re-run" "Bash output cache"

# ---------------------------------------------------------------------------
# Advisory: small cached output (< 10 lines) → no advisory
# ---------------------------------------------------------------------------

small_json="$(jq -cn '{tool_name:"Bash",tool_input:{command:"jq --version"},stdout:"a\nb\nc"}')"
run_hook "$POST_HOOK" "$small_json" "CLAUDE_CONFIG_DIR=${tmp_config}"
run_hook "$PRE_HOOK" '{"tool_name":"Bash","tool_input":{"command":"jq --version"}}' "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_no_cache_advisory "no cache advisory when cached output is small"

# ---------------------------------------------------------------------------
# Advisory: stale cache (past TTL) → no advisory
# ---------------------------------------------------------------------------

stale_cmd="stale-cmd-test"
stale_key="$(cmd_hash "$stale_cmd")"
mkdir -p "$cache_dir"
seq 1 30 | sed 's/^/line /' > "${cache_dir}/${stale_key}.txt"

# Set mtime to 2 hours ago (well past default 600s TTL)
old_ts="$(($(date +%s) - 7200))"
touch -t "$(date -r "$old_ts" '+%Y%m%d%H%M.%S' 2>/dev/null || date -d "@$old_ts" '+%Y%m%d%H%M.%S')" "${cache_dir}/${stale_key}.txt"

run_hook "$PRE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"${stale_cmd}\"}}" "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_stdout_empty "no advisory when cache is past TTL"

# ---------------------------------------------------------------------------
# Advisory: TTL override via RND_BASH_CACHE_TTL_SECONDS
# ---------------------------------------------------------------------------

run_hook "$PRE_HOOK" "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"${stale_cmd}\"}}" "CLAUDE_CONFIG_DIR=${tmp_config} RND_BASH_CACHE_TTL_SECONDS=86400"
assert_stdout_contains "advisory fires when TTL widened to cover stale entry" "Bash output cache"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

rm -rf "$tmp_config"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
