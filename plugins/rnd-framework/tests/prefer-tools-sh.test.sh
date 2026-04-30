#!/usr/bin/env bash
# Tests for hooks/prefer-tools.sh
# Usage: bash tests/prefer-tools-sh.test.sh
# Exits 0 if all tests pass, 1 if any fail.
#
# NOTE: Test payloads that contain $, backticks, or special characters
# use jq to build the JSON so that the command string is properly encoded.

set -euo pipefail

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
# Blocks sed/awk with stderr mentioning "Edit tool", exit 2
# ---------------------------------------------------------------------------

run_hook "$(payload 'sed s/foo/bar/ file.txt')"
assert_exit   "sed → exit 2" 2
assert_stderr_contains "sed → stderr mentions Edit tool" "Edit tool"

run_hook "$(payload "awk '{print \$1}' file")"
assert_exit   "awk → exit 2" 2
assert_stderr_contains "awk → stderr mentions Edit tool" "Edit tool"

# ---------------------------------------------------------------------------
# cat/head/tail/grep/rg/find are NOT blocked (tool-discipline read-side gates removed)
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
# Blocks echo/printf with file redirect to non-.rnd/, non-/dev/ paths
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo foo > output.txt')"
assert_exit   "echo > output.txt → exit 2" 2
assert_stderr_contains "echo > output.txt → Write tool" "Write tool"

run_hook "$(payload "printf '%s' data > file.txt")"
assert_exit   "printf > file.txt → exit 2" 2
assert_stderr_contains "printf > file.txt → Write tool" "Write tool"

run_hook "$(payload 'echo content > /tmp/regular.txt')"
assert_exit   "echo > /tmp/regular.txt → exit 2" 2
assert_stderr_contains "echo > /tmp/regular.txt → Write tool" "Write tool"

# ---------------------------------------------------------------------------
# Allows echo/printf to /dev/ and .rnd/ paths
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
# Allows echo/printf without redirect (outputs allow JSON)
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo hello')"
assert_exit   "echo without redirect → exit 0" 0
assert_stdout_contains "echo without redirect → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload 'printf hello')"
assert_exit   "printf without redirect → exit 0" 0
assert_stdout_contains "printf without redirect → allow JSON" '"permissionDecision":"allow"'

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
# Detects prohibited commands after &&, ;, ||, | operators
# ---------------------------------------------------------------------------

run_hook "$(payload "ls && sed -i 's/old/new/' file")"
assert_exit   "sed after && → exit 2" 2
assert_stderr_contains "sed after && → Edit tool" "Edit tool"

run_hook "$(payload "npm run build && awk '{print \$1}' file")"
assert_exit   "awk after && → exit 2" 2
assert_stderr_contains "awk after && → Edit tool" "Edit tool"

run_hook "$(payload "ls ; awk '{print \$1}' file")"
assert_exit   "awk after ; → exit 2" 2
assert_stderr_contains "awk after ; → Edit tool" "Edit tool"

# read-side tools in compound commands are allowed
run_hook "$(payload 'npm install && cat package.json')"
assert_exit   "cat after && → exit 0 (no opinion)" 0

run_hook "$(payload 'npm run build && head -20 dist/index.js')"
assert_exit   "head after && → exit 0 (no opinion)" 0

run_hook "$(payload 'npm install ; cat package.json')"
assert_exit   "cat after ; → exit 0 (no opinion)" 0

run_hook "$(payload 'test -f file || cat fallback.txt')"
assert_exit   "cat after || → exit 0 (no opinion)" 0

# ---------------------------------------------------------------------------
# Detects prohibited commands inside $() and backtick substitutions
# ---------------------------------------------------------------------------

run_hook "$(payload "echo \$(sed s/a/b/ file)")"
assert_exit   "sed inside \$() → exit 2" 2
assert_stderr_contains "sed inside \$() → Edit tool" "Edit tool"

run_hook "$(payload "ls && echo \`awk '{print \$1}' file\`")"
assert_exit   "awk inside backticks → exit 2" 2
assert_stderr_contains "awk inside backticks → Edit tool" "Edit tool"

# ---------------------------------------------------------------------------
# Strips cd prefixes before checking segments
# ---------------------------------------------------------------------------

run_hook "$(payload 'cd /some/path && sed s/a/b/ f')"
assert_exit   "cd && sed → exit 2 (cd stripped, sed blocked)" 2
assert_stderr_contains "cd && sed → Edit tool" "Edit tool"

run_hook "$(payload 'cd /path && cd /other && ls')"
assert_exit   "cd && cd && ls → exit 0" 0
assert_stdout_empty "cd && cd && ls → empty stdout (no opinion)"

run_hook "$(payload 'cd /path ; sed s/a/b/ f')"
assert_exit   "cd ; sed → exit 2" 2
assert_stderr_contains "cd ; sed → Edit tool" "Edit tool"

run_hook "$(payload 'cd /path; sed s/a/b/ f')"
assert_exit   "cd; sed (no space) → exit 2" 2
assert_stderr_contains "cd; sed (no space) → Edit tool" "Edit tool"

run_hook "$(payload 'cd /a ; cd /b ; sed s/x/y/ file')"
assert_exit   "cd ; cd ; sed → exit 2" 2
assert_stderr_contains "cd ; cd ; sed → Edit tool" "Edit tool"

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

# Tool discipline overrides .rnd/ auto-allow (write-side only: sed/awk still blocked)
run_hook "$(payload 'sed s/foo/bar/ /Users/alice/.claude/.rnd/plan.md')"
assert_exit   "sed .rnd/ → exit 2 (tool discipline overrides)" 2
assert_stderr_contains "sed .rnd/ → Edit tool" "Edit tool"

# cat on .rnd/ is now allowed (read-side gate removed)
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
# Additional correctness checks: echo redirect variations
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo foo > /dev/stderr > /tmp/out')"
assert_exit   "echo > /dev/stderr > /tmp/out → exit 2" 2
assert_stderr_contains "echo multiple redirects → Write tool" "Write tool"

run_hook "$(payload 'printf data > /dev/null > file.txt')"
assert_exit   "printf > /dev/null > file.txt → exit 2" 2
assert_stderr_contains "printf multiple redirects → Write tool" "Write tool"

run_hook "$(payload 'npm test && echo result > output.txt')"
assert_exit   "echo redirect after && → exit 2" 2
assert_stderr_contains "echo redirect after && → Write tool" "Write tool"

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
assert_exit   "npm test && echo results → exit 0 allow" 0
assert_stdout_contains "npm test && echo results → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# Blocks inline interpreter execution (-c/-e flags)
# ---------------------------------------------------------------------------

run_hook "$(payload "python3 -c 'print(\"hi\")'")";
assert_exit   "python3 -c → exit 2" 2
assert_stderr_contains "python3 -c → inline" "inline"

run_hook "$(payload "python -c 'import json; print(json.dumps({}))'")";
assert_exit   "python -c → exit 2" 2
assert_stderr_contains "python -c → inline" "inline"

run_hook "$(payload "node -e 'console.log(1)'")";
assert_exit   "node -e → exit 2" 2
assert_stderr_contains "node -e → inline" "inline"

run_hook "$(payload "bun -e 'console.log(1)'")";
assert_exit   "bun -e → exit 2" 2
assert_stderr_contains "bun -e → inline" "inline"

run_hook "$(payload "bun eval 'code'")";
assert_exit   "bun eval → exit 2" 2
assert_stderr_contains "bun eval → inline" "inline"

run_hook "$(payload "perl -e 'print \"hi\"'")";
assert_exit   "perl -e → exit 2" 2
assert_stderr_contains "perl -e → inline" "inline"

run_hook "$(payload "ruby -e 'puts \"hi\"'")";
assert_exit   "ruby -e → exit 2" 2
assert_stderr_contains "ruby -e → inline" "inline"

# ---------------------------------------------------------------------------
# Blocks piped interpreter execution (bare interpreter after pipe)
# ---------------------------------------------------------------------------

run_hook "$(payload "echo 'code' | python3")";
assert_exit   "echo | python3 → exit 2" 2
assert_stderr_contains "echo | python3 → inline" "inline"

run_hook "$(payload "echo 'code' | node")";
assert_exit   "echo | node → exit 2" 2
assert_stderr_contains "echo | node → inline" "inline"

# ---------------------------------------------------------------------------
# Allows interpreter file execution and module invocation
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
# Blocks /tmp redirects in non-echo commands
# ---------------------------------------------------------------------------

run_hook "$(payload 'npm test > /tmp/log.txt')"
assert_exit   "npm test > /tmp/ → exit 2" 2
assert_stderr_contains "npm test > /tmp/ → /tmp" "/tmp"

run_hook "$(payload 'python3 script.py > /tmp/out')"
assert_exit   "python3 script.py > /tmp/ → exit 2" 2
assert_stderr_contains "python3 script.py > /tmp/ → /tmp" "/tmp"

run_hook "$(payload 'command >> /tmp/append.txt')"
assert_exit   "command >> /tmp/ → exit 2" 2
assert_stderr_contains "command >> /tmp/ → /tmp" "/tmp"

# ---------------------------------------------------------------------------
# /dev/ redirect and non-/tmp redirect are NOT blocked
# ---------------------------------------------------------------------------

run_hook "$(payload 'npm test > /dev/null')"
assert_exit   "npm test > /dev/null → exit 0" 0
assert_stdout_empty "npm test > /dev/null → empty stdout (no opinion)"

run_hook "$(payload 'npm test > output.log')"
assert_exit   "npm test > output.log → exit 0" 0
assert_stdout_empty "npm test > output.log → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# /tmp redirect: compound commands starting with echo/printf
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo Starting && npm test > /tmp/log.txt')"
assert_exit   "echo && npm test > /tmp/ → exit 2 (compound, /tmp guard not skipped)" 2
assert_stderr_contains "echo && npm > /tmp/ → /tmp" "/tmp"

run_hook "$(payload 'printf msg && pytest >> /tmp/out.txt')"
assert_exit   "printf && pytest >> /tmp/ → exit 2" 2
assert_stderr_contains "printf && pytest >> /tmp/ → /tmp" "/tmp"

# Simple echo > /tmp/ still gets "Write tool" message from check_echo_redirect
run_hook "$(payload 'echo content > /tmp/regular.txt')"
assert_exit   "echo > /tmp/ (simple) → exit 2" 2
assert_stderr_contains "echo > /tmp/ (simple) → Write tool" "Write tool"

# ---------------------------------------------------------------------------
# Env-var prefix: tool discipline detects commands after FOO=bar
# ---------------------------------------------------------------------------

run_hook "$(payload 'FOO=bar sed s/a/b/ file')"
assert_exit   "FOO=bar sed → exit 2" 2
assert_stderr_contains "FOO=bar sed → Edit tool" "Edit tool"

run_hook "$(payload 'FOO=bar BAZ=quux sed s/a/b/ file')"
assert_exit   "FOO=bar BAZ=quux sed → exit 2 (multiple env vars)" 2
assert_stderr_contains "FOO=bar BAZ=quux sed → Edit tool" "Edit tool"

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

# Env-var prefix in compound command (read-side allowed, write-side blocked)
run_hook "$(payload 'ENV_VAR=value npm test && grep pattern file')"
assert_exit   "ENV_VAR=value npm test && grep → exit 0" 0

run_hook "$(payload 'ENV_VAR=value npm test && sed s/a/b/ file')"
assert_exit   "ENV_VAR=value npm test && sed → exit 2" 2
assert_stderr_contains "ENV_VAR=value && sed → Edit tool" "Edit tool"

# Env-var prefix with git push advisory
run_hook "$(payload 'FOO=bar git push origin main')"
assert_exit   "FOO=bar git push main → exit 0 (advisory)" 0
assert_stdout_contains "FOO=bar git push main → advisory" "systemMessage"

# ---------------------------------------------------------------------------
# /tmp redirect: no-space before > (cmd>/tmp/out)
# ---------------------------------------------------------------------------

run_hook "$(payload 'npm test>/tmp/log.txt')"
assert_exit   "npm test>/tmp/ (no space) → exit 2" 2
assert_stderr_contains "npm test>/tmp/ (no space) → /tmp" "/tmp"

# ---------------------------------------------------------------------------
# Information barrier: self-assessment commands
# ---------------------------------------------------------------------------

# verifier running diff on self-assessment → blocked
run_hook "$(payload_with_agent 'diff /rnd/builds/T3-self-assessment.md /tmp/x' 'rnd-verifier')"
assert_exit   "diff self-assessment + verifier → exit 2" 2
assert_stderr_contains "diff self-assessment + verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# empty agent_type running jq on self-assessment → blocked
run_hook "$(payload_with_agent 'jq . /rnd/builds/T3-self-assessment.md' '')"
assert_exit   "jq self-assessment + empty agent_type → exit 2" 2
assert_stderr_contains "jq self-assessment + empty agent_type → INFORMATION BARRIER" "INFORMATION BARRIER"

# missing agent_type key (null from jq) → blocked
run_hook "$(jq -n --arg cmd 'less /rnd/builds/T3-self-assessment.md' '{"tool_name":"Bash","tool_input":{"command":$cmd}}')"
assert_exit   "less self-assessment + null agent_type → exit 2" 2
assert_stderr_contains "less self-assessment + null agent_type → INFORMATION BARRIER" "INFORMATION BARRIER"

# builder running self-assessment command → allowed (exit 0)
run_hook "$(payload_with_agent 'wc -l /rnd/builds/T3-self-assessment.md' 'rnd-builder')"
assert_exit   "wc self-assessment + rnd-builder → exit 0" 0

# case-insensitive: SELF-ASSESSMENT uppercase + verifier → blocked
run_hook "$(payload_with_agent 'strings /rnd/builds/T3-SELF-ASSESSMENT.md' 'rnd-verifier')"
assert_exit   "SELF-ASSESSMENT uppercase + verifier → exit 2" 2
assert_stderr_contains "SELF-ASSESSMENT uppercase + verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# case-insensitive: Self-Assessment mixed case + empty agent → blocked
run_hook "$(payload_with_agent 'ls /rnd/builds/T3-Self-Assessment.md' '')"
assert_exit   "Self-Assessment mixed case + empty agent → exit 2" 2
assert_stderr_contains "Self-Assessment mixed case + empty agent → INFORMATION BARRIER" "INFORMATION BARRIER"

# barrier fires before tool discipline: diff is not blocked by tool discipline, but barrier catches it
run_hook "$(payload_with_agent 'diff T3-self-assessment.md other.md' 'rnd-verifier')"
assert_exit   "diff (not tool-discipline-blocked) + verifier + self-assessment → exit 2" 2
assert_stderr_contains "diff (barrier before discipline) → INFORMATION BARRIER" "INFORMATION BARRIER"

# non-self-assessment .rnd/ path + verifier → not blocked by barrier (auto-allow or no-opinion)
run_hook "$(payload_with_agent 'ls /home/.claude/.rnd/builds/T3-manifest.md' 'rnd-verifier')"
assert_exit   ".rnd/ manifest path + verifier → exit 0 (no barrier)" 0

# existing tool-discipline blocks still work after barrier is in place
run_hook "$(payload 'sed s/foo/bar/ file.txt')"
assert_exit   "sed still blocked after barrier code added → exit 2" 2
assert_stderr_contains "sed still blocked → Edit tool" "Edit tool"

# bfs with self-assessment path + verifier → barrier blocks
run_hook "$(payload_with_agent 'bfs /rnd/builds/T3-self-assessment.md' 'rnd-verifier')"
assert_exit   "bfs self-assessment + verifier → exit 2" 2
assert_stderr_contains "bfs self-assessment + verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# ugrep with /briefs/ path + verifier → barrier blocks
run_hook "$(payload_with_agent 'ugrep -r pattern /rnd/briefs/' 'rnd-verifier')"
assert_exit   "ugrep /briefs/ + verifier → exit 2" 2
assert_stderr_contains "ugrep /briefs/ + verifier → INFORMATION BARRIER" "INFORMATION BARRIER"

# bfs with self-assessment path + builder → allowed (barrier does not fire)
run_hook "$(payload_with_agent 'bfs /rnd/builds/T3-self-assessment.md' 'rnd-builder')"
assert_exit   "bfs self-assessment + rnd-builder → exit 0" 0

# ugrep with briefs/ path + builder → allowed (barrier does not fire)
run_hook "$(payload_with_agent 'ugrep -r pattern /rnd/briefs/' 'rnd-builder')"
assert_exit   "ugrep /briefs/ + rnd-builder → exit 0" 0

# ---------------------------------------------------------------------------
# Env-var prefix with quoted value containing internal space — now blocked.
# strip_env_prefix detects an unmatched leading quote in the value portion of
# first_word (e.g. FOO="abc) and emits a blocked: message rather than attempting
# to strip an incomplete prefix. Result: exit 2 (blocked).
# ---------------------------------------------------------------------------

run_hook "$(payload 'FOO="abc def" sed s/a/b/ file')"
assert_exit   'FOO="abc def" sed → exit 2 (unmatched-quote env prefix blocked)' 2
assert_stderr_contains 'FOO="abc def" sed → blocked message' 'BLOCKED'

# ---------------------------------------------------------------------------
# Shell loop guard: simple for-loop is detected and blocked (bracket-class fix)
# ---------------------------------------------------------------------------

run_hook "$(payload 'for i in 1; do echo hi; done')"
assert_exit   "for i in 1; do echo hi; done → exit 2 (loop guard)" 2
assert_stderr_contains "for-loop → loop guard message" "for"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
