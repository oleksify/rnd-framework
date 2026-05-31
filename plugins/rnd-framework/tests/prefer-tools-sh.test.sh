#!/usr/bin/env bash
# Tests for hooks/prefer-tools.sh
# Usage: bash tests/prefer-tools-sh.test.sh
# Exits 0 if all tests pass, 1 if any fail.
#
# NOTE: Test payloads that contain $, backticks, or special characters
# use jq to build the JSON so that the command string is properly encoded.

set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/bash-gate.sh"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_hook() {
  local stdin_json="$1"
  HOOK_STDOUT=""
  HOOK_STDERR=""
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$stdin_json" | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# Build a hook payload from a command string, properly JSON-encoding it.
payload() {
  jq -n --arg cmd "$1" '{"tool_name":"Bash","tool_input":{"command":$cmd},"agent_type":""}'
}

# Build a hook payload with agent_type included.
payload_with_agent() {
  jq -n --arg cmd "$1" --arg agent "$2" '{"tool_name":"Bash","tool_input":{"command":$cmd},"agent_type":$agent}'
}

pass() {
  local name="$1"
  printf 'PASS  %s\n' "$name"
  PASS=$((PASS + 1))
}

fail() {
  local name="$1"
  local detail="$2"
  printf 'FAIL  %s — %s\n' "$name" "$detail"
  FAIL=$((FAIL + 1))
}

assert_exit() {
  local name="$1"
  local expected="$2"
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expected, got $HOOK_EXIT"
  fi
}

assert_stdout_contains() {
  local name="$1"
  local needle="$2"
  if [[ "$HOOK_STDOUT" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected stdout to contain '$needle', got: '$HOOK_STDOUT'"
  fi
}

assert_stdout_empty() {
  local name="$1"
  if [[ -z "$(printf '%s' "$HOOK_STDOUT" | tr -d '[:space:]')" ]]; then
    pass "$name"
  else
    fail "$name" "expected empty stdout, got: '$HOOK_STDOUT'"
  fi
}

assert_stderr_contains() {
  local name="$1"
  local needle="$2"
  if [[ "$HOOK_STDERR" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected stderr to contain '$needle', got: '$HOOK_STDERR'"
  fi
}

# ---------------------------------------------------------------------------
# cat/head/tail/grep/rg/find are NOT blocked (read-side tools always allowed)
# ---------------------------------------------------------------------------

run_hook "$(payload 'cat somefile')"
assert_exit   "cat → exit 0 (no opinion)" 0
assert_stdout_empty "cat → empty stdout (no opinion)"

run_hook "$(payload 'head -n 10 file')"
assert_exit   "head → exit 0 (no opinion)" 0
assert_stdout_empty "head → empty stdout (no opinion)"

run_hook "$(payload 'tail -n 10 file.txt')"
assert_exit   "tail with file arg → exit 0 (no opinion)" 0
assert_stdout_empty "tail with file arg → empty stdout (no opinion)"

run_hook "$(payload 'grep pattern file')"
assert_exit   "grep → exit 0 (no opinion)" 0
assert_stdout_empty "grep → empty stdout (no opinion)"

run_hook "$(payload 'rg pattern file.txt')"
assert_exit   "rg with file → exit 0 (no opinion)" 0
assert_stdout_empty "rg with file → empty stdout (no opinion)"

run_hook "$(payload 'grep -r pattern')"
assert_exit   "grep -r → exit 0 (no opinion)" 0
assert_stdout_empty "grep -r → empty stdout (no opinion)"

run_hook "$(payload "find . -name '*.ts'")"
assert_exit   "find → exit 0 (no opinion)" 0
assert_stdout_empty "find → empty stdout (no opinion)"

# Pipe-filter forms still work
run_hook "$(payload 'pnpm check 2>&1 | tail -30')"
assert_exit   "tail pipe filter → exit 0" 0

run_hook "$(payload 'npm test | grep FAIL')"
assert_exit   "grep pipe filter → exit 0" 0

# ---------------------------------------------------------------------------
# echo/printf: /dev/ and .rnd/ paths pass through; .rnd/ gets auto-allow JSON
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo foo > /dev/null')"
assert_exit   "echo > /dev/null → exit 0" 0

run_hook "$(payload 'echo foo > /dev/stderr')"
assert_exit   "echo > /dev/stderr → exit 0" 0

run_hook "$(payload_with_agent 'echo DONE > /home/user/.claude/.rnd/builds/T1-self-assessment.md' 'rnd-builder')"
assert_exit   "echo > .rnd/ → exit 0" 0
assert_stdout_contains "echo > .rnd/ → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload "printf 'DONE' > /home/user/.claude/.rnd/builds/T1-manifest.md")"
assert_exit   "printf > .rnd/ → exit 0" 0
assert_stdout_contains "printf > .rnd/ → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# echo/printf without redirect: exit 0, no opinion
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo hello')"
assert_exit   "echo without redirect → exit 0" 0
assert_stdout_empty "echo without redirect → empty stdout (no opinion)"

run_hook "$(payload 'printf hello')"
assert_exit   "printf without redirect → exit 0" 0
assert_stdout_empty "printf without redirect → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# Blocks git add .rnd/ with stderr "BLOCKED", exit 2
# ---------------------------------------------------------------------------

run_hook "$(payload 'git add .rnd/something')"
assert_exit   "git add .rnd/ → exit 2" 2
assert_stderr_contains "git add .rnd/ → BLOCKED" "BLOCKED"

run_hook "$(payload 'git add .rnd/')"
assert_exit   "git add .rnd/ (trailing slash) → exit 2" 2
assert_stderr_contains "git add .rnd/ (trailing slash) → BLOCKED" "BLOCKED"

run_hook "$(payload 'git add some/path/.rnd/file')"
assert_exit   "git add nested .rnd/ → exit 2" 2
assert_stderr_contains "git add nested .rnd/ → BLOCKED" "BLOCKED"

# False positive guard: .rnd.backup should NOT be blocked
run_hook "$(payload 'git add .rnd.backup')"
assert_exit   "git add .rnd.backup → exit 0 (not a .rnd/ path)" 0
assert_stdout_empty "git add .rnd.backup → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# Advisory warning on git push to main/master/production (exit 0, advisory JSON)
# ---------------------------------------------------------------------------

run_hook "$(payload 'git push origin main')"
assert_exit   "git push origin main → exit 0 (advisory)" 0
assert_stdout_contains "git push origin main → advisory" "systemMessage"

run_hook "$(payload 'git push origin master')"
assert_exit   "git push origin master → exit 0 (advisory)" 0
assert_stdout_contains "git push origin master → advisory" "systemMessage"

run_hook "$(payload 'git push origin production')"
assert_exit   "git push origin production → exit 0 (advisory)" 0
assert_stdout_contains "git push origin production → advisory" "systemMessage"

# Non-protected branches should pass through
run_hook "$(payload 'git push origin feature-branch')"
assert_exit   "git push feature-branch → exit 0" 0
assert_stdout_empty "git push feature-branch → empty stdout (no opinion)"

run_hook "$(payload 'git push --tags')"
assert_exit   "git push --tags → exit 0" 0
assert_stdout_empty "git push --tags → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# read-side tools in compound commands are allowed
# ---------------------------------------------------------------------------

run_hook "$(payload 'npm install && cat package.json')"
assert_exit   "cat after && → exit 0 (no opinion)" 0

run_hook "$(payload 'npm run build && head -20 dist/index.js')"
assert_exit   "head after && → exit 0 (no opinion)" 0

run_hook "$(payload 'npm install ; cat package.json')"
assert_exit   "cat after ; → exit 0 (no opinion)" 0

run_hook "$(payload 'test -f file || cat fallback.txt')"
assert_exit   "cat after || → exit 0 (no opinion)" 0

# ---------------------------------------------------------------------------
# cd prefix stripping: cd chains pass through
# ---------------------------------------------------------------------------

run_hook "$(payload 'cd /path && cd /other && ls')"
assert_exit   "cd && cd && ls → exit 0" 0
assert_stdout_empty "cd && cd && ls → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# Auto-allows commands containing .rnd/ or rnd-dir.sh
# ---------------------------------------------------------------------------

run_hook "$(payload 'ls /Users/alice/.claude/.rnd/builds')"
assert_exit   ".rnd/ in command → exit 0" 0
assert_stdout_contains ".rnd/ in command → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload 'bun run /Users/alice/.claude/.rnd/builds/check.ts')"
assert_exit   ".rnd/ in non-ls command → exit 0" 0
assert_stdout_contains ".rnd/ in non-ls command → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload 'RND_DIR="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")"')"
assert_exit   "rnd-dir.sh in command → exit 0" 0
assert_stdout_contains "rnd-dir.sh → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload 'npm install && bun run /Users/alice/.claude/.rnd/check.ts')"
assert_exit   ".rnd/ after && → exit 0 allow" 0
assert_stdout_contains ".rnd/ after && → allow JSON" '"permissionDecision":"allow"'

# cat on .rnd/ is auto-allowed
run_hook "$(payload 'cat /Users/alice/.claude/.rnd/builds/manifest.md')"
assert_exit   "cat .rnd/ → exit 0 (auto-allow)" 0
assert_stdout_contains "cat .rnd/ → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# Auto-allows commands containing ${CLAUDE_PLUGIN_ROOT}/lib/
# When CLAUDE_PLUGIN_ROOT is unset we use a deterministic fake root to test
# the matching logic. The hook is invoked with that value in its environment.
# ---------------------------------------------------------------------------

fake_plugin_root="/tmp/fake-plugin-root-$$"
HOOK_EXIT=0
HOOK_STDOUT=""
HOOK_STDERR=""
tmp_out="$(mktemp)"
tmp_err="$(mktemp)"
printf '%s' "$(payload "${fake_plugin_root}/lib/bump.sh")" \
  | CLAUDE_PLUGIN_ROOT="$fake_plugin_root" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$tmp_out")"
HOOK_STDERR="$(cat "$tmp_err")"
rm -f "$tmp_out" "$tmp_err"
assert_exit   "plugin lib/ script → exit 0" 0
assert_stdout_contains "plugin lib/ script → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# Empty or malformed stdin → exits 0
# ---------------------------------------------------------------------------

printf '' | "$HOOK" >/dev/null 2>/dev/null
HOOK_EXIT=$?
if [[ "$HOOK_EXIT" -eq 0 ]]; then
  pass "empty stdin → exit 0"
else
  fail "empty stdin → exit 0" "got exit $HOOK_EXIT"
fi

run_hook 'not valid json at all'
assert_exit   "non-JSON stdin → exit 0" 0

run_hook '{"no_tool_input":"here"}'
assert_exit   "JSON without tool_input → exit 0" 0

# ---------------------------------------------------------------------------
# git add .rnd/ via compound command; git push advisory via compound command
# ---------------------------------------------------------------------------

run_hook "$(payload 'npm test && echo result > /dev/null')"
assert_exit   "echo > /dev/null after && → exit 0" 0

run_hook "$(payload 'npm test && echo result > /Users/alice/.claude/.rnd/builds/out.md')"
assert_exit   "echo > .rnd/ after && → exit 0" 0

# git add .rnd/ after && should be blocked via full-command git guard
run_hook "$(payload 'cd /some/path && git add .rnd/file')"
assert_exit   "cd && git add .rnd/ → exit 2" 2
assert_stderr_contains "cd && git add .rnd/ → BLOCKED" "BLOCKED"

# git push main after && should emit advisory via full-command git guard
run_hook "$(payload 'npm install && git push origin main')"
assert_exit   "npm && git push main → exit 0 (advisory)" 0
assert_stdout_contains "npm && git push main → advisory" "systemMessage"

# No-opinion cases
run_hook "$(payload 'ls -la')"
assert_exit   "ls -la → exit 0 (no opinion)" 0
assert_stdout_empty "ls -la → empty stdout"

run_hook "$(payload 'npm install')"
assert_exit   "npm install → exit 0 (no opinion)" 0
assert_stdout_empty "npm install → empty stdout"

run_hook "$(payload 'npm test && echo results')"
assert_exit   "npm test && echo results → exit 0" 0

# ---------------------------------------------------------------------------
# Interpreter invocations: all forms pass through
# ---------------------------------------------------------------------------

run_hook "$(payload 'python file.py')"
assert_exit   "python file.py → exit 0" 0
assert_stdout_empty "python file.py → empty stdout (no opinion)"

run_hook "$(payload 'python3 /path/to/script.py')"
assert_exit   "python3 /path → exit 0" 0
assert_stdout_empty "python3 /path → empty stdout (no opinion)"

run_hook "$(payload 'python -m pytest')"
assert_exit   "python -m pytest → exit 0" 0
assert_stdout_empty "python -m pytest → empty stdout (no opinion)"

run_hook "$(payload 'python3 -m http.server')"
assert_exit   "python3 -m http.server → exit 0" 0
assert_stdout_empty "python3 -m http.server → empty stdout (no opinion)"

run_hook "$(payload 'python3 -c "print(1)"')"
assert_exit   "python3 -c → exit 0 (pass-through)" 0

run_hook "$(payload 'node -e "console.log(1)"')"
assert_exit   "node -e → exit 0 (pass-through)" 0

run_hook "$(payload 'bun test')"
assert_exit   "bun test → exit 0" 0
assert_stdout_empty "bun test → empty stdout (no opinion)"

run_hook "$(payload 'bun run start.ts')"
assert_exit   "bun run start.ts → exit 0" 0
assert_stdout_empty "bun run start.ts → empty stdout (no opinion)"

run_hook "$(payload 'bun install')"
assert_exit   "bun install → exit 0" 0
assert_stdout_empty "bun install → empty stdout (no opinion)"

run_hook "$(payload 'bun add package')"
assert_exit   "bun add → exit 0" 0
assert_stdout_empty "bun add → empty stdout (no opinion)"

run_hook "$(payload 'node script.js')"
assert_exit   "node script.js → exit 0" 0
assert_stdout_empty "node script.js → empty stdout (no opinion)"

run_hook "$(payload 'lake build')"
assert_exit   "lake build → exit 0 (not an interpreter match)" 0
assert_stdout_empty "lake build → empty stdout (no opinion)"

run_hook "$(payload 'lean file.lean')"
assert_exit   "lean file.lean → exit 0 (not an interpreter match)" 0
assert_stdout_empty "lean file.lean → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# /dev/ redirect and /tmp redirect are NOT blocked
# ---------------------------------------------------------------------------

run_hook "$(payload 'npm test > /dev/null')"
assert_exit   "npm test > /dev/null → exit 0" 0
assert_stdout_empty "npm test > /dev/null → empty stdout (no opinion)"

run_hook "$(payload 'npm test > output.log')"
assert_exit   "npm test > output.log → exit 0" 0
assert_stdout_empty "npm test > output.log → empty stdout (no opinion)"

run_hook "$(payload 'npm test > /tmp/log.txt')"
assert_exit   "npm test > /tmp/ → exit 0 (pass-through)" 0

# ---------------------------------------------------------------------------
# Env-var prefix: read-side commands and git advisory preserved
# ---------------------------------------------------------------------------

# read-side commands with env prefix are allowed
run_hook "$(payload 'FOO=bar cat somefile')"
assert_exit   "FOO=bar cat → exit 0" 0

run_hook "$(payload 'FOO=bar grep pattern file')"
assert_exit   "FOO=bar grep → exit 0" 0

run_hook "$(payload "FOO=bar find . -name '*.ts'")"
assert_exit   "FOO=bar find → exit 0" 0

# Env-var prefix: non-blocked commands still pass
run_hook "$(payload 'FOO=bar npm test')"
assert_exit   "FOO=bar npm test → exit 0" 0
assert_stdout_empty "FOO=bar npm test → empty stdout"

run_hook "$(payload 'MIX_ENV=test mix ecto.reset')"
assert_exit   "MIX_ENV=test mix ecto.reset → exit 0 (allowed)" 0

# Env-var prefix in compound command
run_hook "$(payload 'ENV_VAR=value npm test && grep pattern file')"
assert_exit   "ENV_VAR=value npm test && grep → exit 0" 0

# Env-var prefix with git push advisory
run_hook "$(payload 'FOO=bar git push origin main')"
assert_exit   "FOO=bar git push main → exit 0 (advisory)" 0
assert_stdout_contains "FOO=bar git push main → advisory" "systemMessage"

# ---------------------------------------------------------------------------
# Information barrier: self-assessment commands
# ---------------------------------------------------------------------------

# verifier running diff on self-assessment → blocked
run_hook "$(payload_with_agent 'diff /rnd/builds/T3-self-assessment.md /tmp/x' 'rnd-verifier')"
assert_exit   "diff self-assessment + verifier → exit 2" 2
assert_stderr_contains "diff self-assessment + verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# empty agent_type running jq on self-assessment → allowed (orchestrator is the legitimate consumer)
run_hook "$(payload_with_agent 'jq . /rnd/builds/T3-self-assessment.md' '')"
assert_exit   "jq self-assessment + empty agent_type → exit 0 (orchestrator allowed)" 0

# missing agent_type key (null from jq) → allowed (treated as orchestrator)
run_hook "$(jq -n --arg cmd 'less /rnd/builds/T3-self-assessment.md' '{"tool_name":"Bash","tool_input":{"command":$cmd}}')"
assert_exit   "less self-assessment + null agent_type → exit 0 (orchestrator allowed)" 0

# builder running self-assessment command → allowed (exit 0)
run_hook "$(payload_with_agent 'wc -l /rnd/builds/T3-self-assessment.md' 'rnd-builder')"
assert_exit   "wc self-assessment + rnd-builder → exit 0" 0

# case-insensitive: SELF-ASSESSMENT uppercase + verifier → blocked
run_hook "$(payload_with_agent 'strings /rnd/builds/T3-SELF-ASSESSMENT.md' 'rnd-verifier')"
assert_exit   "SELF-ASSESSMENT uppercase + verifier → exit 2" 2
assert_stderr_contains "SELF-ASSESSMENT uppercase + verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# case-insensitive: Self-Assessment mixed case + empty agent → allowed (orchestrator)
run_hook "$(payload_with_agent 'ls /rnd/builds/T3-Self-Assessment.md' '')"
assert_exit   "Self-Assessment mixed case + empty agent → exit 0 (orchestrator allowed)" 0

# barrier fires before other checks: diff is not otherwise blocked, but barrier catches it
run_hook "$(payload_with_agent 'diff T3-self-assessment.md other.md' 'rnd-verifier')"
assert_exit   "diff (not otherwise blocked) + verifier + self-assessment → exit 2" 2
assert_stderr_contains "diff (barrier before other checks) → INFORMATION BARRIER" "INFORMATION BARRIER"

# non-self-assessment .rnd/ path + verifier → not blocked by barrier (auto-allow or no-opinion)
run_hook "$(payload_with_agent 'ls /home/.claude/.rnd/builds/T3-manifest.md' 'rnd-verifier')"
assert_exit   ".rnd/ manifest path + verifier → exit 0 (no barrier)" 0

# bfs with self-assessment path + verifier → barrier blocks
run_hook "$(payload_with_agent 'bfs /rnd/builds/T3-self-assessment.md' 'rnd-verifier')"
assert_exit   "bfs self-assessment + verifier → exit 2" 2
assert_stderr_contains "bfs self-assessment + verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# ugrep with /briefs/ path + verifier → barrier blocks (realistic .rnd/ artifact path)
run_hook "$(payload_with_agent 'ugrep -r pattern /home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/' 'rnd-verifier')"
assert_exit   "ugrep /briefs/ + verifier → exit 2" 2
assert_stderr_contains "ugrep /briefs/ + verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# bfs with self-assessment path + builder → allowed (barrier does not fire)
run_hook "$(payload_with_agent 'bfs /rnd/builds/T3-self-assessment.md' 'rnd-builder')"
assert_exit   "bfs self-assessment + rnd-builder → exit 0" 0

# ugrep with briefs/ path + builder → allowed (barrier does not fire)
run_hook "$(payload_with_agent 'ugrep -r pattern /home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/' 'rnd-builder')"
assert_exit   "ugrep /briefs/ + rnd-builder → exit 0" 0

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
