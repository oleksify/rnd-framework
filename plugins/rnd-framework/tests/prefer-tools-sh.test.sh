#!/usr/bin/env bash
# Tests for hooks/prefer-tools.sh
# Usage: bash tests/prefer-tools-sh.test.sh
# Exits 0 if all tests pass, 1 if any fail.
#
# NOTE: Test payloads that contain $, backticks, or special characters
# use jq to build the JSON so that the command string is properly encoded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/prefer-tools.sh"

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
  jq -n --arg cmd "$1" '{"tool_input":{"command":$cmd}}'
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
# T14 Criterion: Blocks sed/awk with stderr mentioning "Edit tool", exit 2
# ---------------------------------------------------------------------------

run_hook "$(payload 'sed s/foo/bar/ file.txt')"
assert_exit   "sed → exit 2" 2
assert_stderr_contains "sed → stderr mentions Edit tool" "Edit tool"

run_hook "$(payload "awk '{print \$1}' file")"
assert_exit   "awk → exit 2" 2
assert_stderr_contains "awk → stderr mentions Edit tool" "Edit tool"

# ---------------------------------------------------------------------------
# T14 Criterion: Blocks cat/head/tail with stderr mentioning "Read tool", exit 2
# ---------------------------------------------------------------------------

run_hook "$(payload 'cat somefile')"
assert_exit   "cat → exit 2" 2
assert_stderr_contains "cat → stderr mentions Read tool" "Read tool"

run_hook "$(payload 'head -n 10 file')"
assert_exit   "head → exit 2" 2
assert_stderr_contains "head → stderr mentions Read tool" "Read tool"

run_hook "$(payload 'tail -f file')"
assert_exit   "tail → exit 2" 2
assert_stderr_contains "tail → stderr mentions Read tool" "Read tool"

# ---------------------------------------------------------------------------
# T14 Criterion: Blocks grep/rg with stderr mentioning "Grep tool", exit 2
# ---------------------------------------------------------------------------

run_hook "$(payload 'grep pattern file')"
assert_exit   "grep → exit 2" 2
assert_stderr_contains "grep → stderr mentions Grep tool" "Grep tool"

run_hook "$(payload 'rg pattern')"
assert_exit   "rg → exit 2" 2
assert_stderr_contains "rg → stderr mentions Grep tool" "Grep tool"

# ---------------------------------------------------------------------------
# T14 Criterion: Blocks find with stderr mentioning "Glob tool", exit 2
# ---------------------------------------------------------------------------

run_hook "$(payload "find . -name '*.ts'")"
assert_exit   "find → exit 2" 2
assert_stderr_contains "find → stderr mentions Glob tool" "Glob tool"

# ---------------------------------------------------------------------------
# T14 Criterion: Blocks echo/printf with file redirect to non-.rnd/, non-/dev/ paths
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
# T14 Criterion: Allows echo/printf to /dev/ and .rnd/ paths
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo foo > /dev/null')"
assert_exit   "echo > /dev/null → exit 0" 0

run_hook "$(payload 'echo foo > /dev/stderr')"
assert_exit   "echo > /dev/stderr → exit 0" 0

run_hook "$(payload 'echo DONE > /home/user/.rnd/builds/T1-self-assessment.md')"
assert_exit   "echo > .rnd/ → exit 0" 0
assert_stdout_contains "echo > .rnd/ → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload "printf 'DONE' > /home/user/.rnd/builds/T1-manifest.md")"
assert_exit   "printf > .rnd/ → exit 0" 0
assert_stdout_contains "printf > .rnd/ → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# T14 Criterion: Allows echo/printf without redirect (outputs allow JSON)
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo hello')"
assert_exit   "echo without redirect → exit 0" 0
assert_stdout_contains "echo without redirect → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload 'printf hello')"
assert_exit   "printf without redirect → exit 0" 0
assert_stdout_contains "printf without redirect → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# T14 Criterion: Blocks git add .rnd/ with stderr "BLOCKED", exit 2
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
# T14 Criterion: Blocks git push to main/master/production with stderr "BLOCKED", exit 2
# ---------------------------------------------------------------------------

run_hook "$(payload 'git push origin main')"
assert_exit   "git push origin main → exit 2" 2
assert_stderr_contains "git push origin main → BLOCKED" "BLOCKED"

run_hook "$(payload 'git push origin master')"
assert_exit   "git push origin master → exit 2" 2
assert_stderr_contains "git push origin master → BLOCKED" "BLOCKED"

run_hook "$(payload 'git push origin production')"
assert_exit   "git push origin production → exit 2" 2
assert_stderr_contains "git push origin production → BLOCKED" "BLOCKED"

# Non-protected branches should pass through
run_hook "$(payload 'git push origin feature-branch')"
assert_exit   "git push feature-branch → exit 0" 0
assert_stdout_empty "git push feature-branch → empty stdout (no opinion)"

run_hook "$(payload 'git push --tags')"
assert_exit   "git push --tags → exit 0" 0
assert_stdout_empty "git push --tags → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# T14 Criterion: Detects prohibited commands after &&, ;, ||, | operators
# ---------------------------------------------------------------------------

run_hook "$(payload 'npm install && cat package.json')"
assert_exit   "cat after && → exit 2" 2
assert_stderr_contains "cat after && → Read tool" "Read tool"

run_hook "$(payload "ls && sed -i 's/old/new/' file")"
assert_exit   "sed after && → exit 2" 2
assert_stderr_contains "sed after && → Edit tool" "Edit tool"

run_hook "$(payload "mkdir dir && find . -name '*.ts'")"
assert_exit   "find after && → exit 2" 2
assert_stderr_contains "find after && → Glob tool" "Glob tool"

run_hook "$(payload 'npm run build && head -20 dist/index.js')"
assert_exit   "head after && → exit 2" 2
assert_stderr_contains "head after && → Read tool" "Read tool"

run_hook "$(payload "npm run build && awk '{print \$1}' file")"
assert_exit   "awk after && → exit 2" 2
assert_stderr_contains "awk after && → Edit tool" "Edit tool"

run_hook "$(payload "ls ; awk '{print \$1}' file")"
assert_exit   "awk after ; → exit 2" 2
assert_stderr_contains "awk after ; → Edit tool" "Edit tool"

run_hook "$(payload 'npm install ; cat package.json')"
assert_exit   "cat after ; → exit 2" 2
assert_stderr_contains "cat after ; → Read tool" "Read tool"

run_hook "$(payload 'npm test | grep FAIL')"
assert_exit   "grep after | → exit 2" 2
assert_stderr_contains "grep after | → Grep tool" "Grep tool"

run_hook "$(payload 'true | rg pattern')"
assert_exit   "rg after | → exit 2" 2
assert_stderr_contains "rg after | → Grep tool" "Grep tool"

run_hook "$(payload 'test -f file || cat fallback.txt')"
assert_exit   "cat after || → exit 2" 2
assert_stderr_contains "cat after || → Read tool" "Read tool"

# ---------------------------------------------------------------------------
# T14 Criterion: Detects prohibited commands inside $() and backtick substitutions
# ---------------------------------------------------------------------------

run_hook "$(payload 'echo $(grep pattern file)')"
assert_exit   "grep inside \$() → exit 2" 2
assert_stderr_contains "grep inside \$() → Grep tool" "Grep tool"

run_hook "$(payload 'echo $(cat secrets.txt)')"
assert_exit   "cat inside \$() → exit 2" 2
assert_stderr_contains "cat inside \$() → Read tool" "Read tool"

run_hook "$(payload 'echo `cat file.txt`')"
assert_exit   "cat inside backticks → exit 2" 2
assert_stderr_contains "cat inside backticks → Read tool" "Read tool"

# Subshell () detection
run_hook "$(payload '(cat file.txt)')"
assert_exit   "cat inside subshell () → exit 2" 2
assert_stderr_contains "cat inside subshell () → Read tool" "Read tool"

run_hook "$(payload '(grep pattern file)')"
assert_exit   "grep inside subshell () → exit 2" 2
assert_stderr_contains "grep inside subshell () → Grep tool" "Grep tool"

# ---------------------------------------------------------------------------
# T14 Criterion: Strips cd prefixes before checking segments
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

run_hook "$(payload 'cd /a ; cd /b ; cat file')"
assert_exit   "cd ; cd ; cat → exit 2" 2
assert_stderr_contains "cd ; cd ; cat → Read tool" "Read tool"

# ---------------------------------------------------------------------------
# T14 Criterion: Auto-allows commands containing .rnd/ or rnd-dir.sh
# ---------------------------------------------------------------------------

run_hook "$(payload 'ls /some/.rnd/builds')"
assert_exit   ".rnd/ in command → exit 0" 0
assert_stdout_contains ".rnd/ in command → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload 'bun run /tmp/.rnd/builds/check.ts')"
assert_exit   ".rnd/ in non-ls command → exit 0" 0
assert_stdout_contains ".rnd/ in non-ls command → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload 'RND_DIR="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")"')"
assert_exit   "rnd-dir.sh in command → exit 0" 0
assert_stdout_contains "rnd-dir.sh → allow JSON" '"permissionDecision":"allow"'

run_hook "$(payload 'npm install && bun run /tmp/.rnd/check.ts')"
assert_exit   ".rnd/ after && → exit 0 allow" 0
assert_stdout_contains ".rnd/ after && → allow JSON" '"permissionDecision":"allow"'

# Tool discipline overrides .rnd/ auto-allow
run_hook "$(payload 'cat /path/.rnd/builds/manifest.md')"
assert_exit   "cat .rnd/ → exit 2 (tool discipline overrides)" 2
assert_stderr_contains "cat .rnd/ → Read tool" "Read tool"

run_hook "$(payload 'sed s/foo/bar/ /path/.rnd/plan.md')"
assert_exit   "sed .rnd/ → exit 2 (tool discipline overrides)" 2
assert_stderr_contains "sed .rnd/ → Edit tool" "Edit tool"

# ---------------------------------------------------------------------------
# T14 Criterion: Auto-allows commands containing ${CLAUDE_PLUGIN_ROOT}/lib/
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
# T14 Criterion: Empty or malformed stdin → exits 0
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

run_hook "$(payload 'npm test && echo result > /path/.rnd/builds/out.md')"
assert_exit   "echo > .rnd/ after && → exit 0" 0

# git add .rnd/ after && should be blocked via full-command git guard
run_hook "$(payload 'cd /some/path && git add .rnd/file')"
assert_exit   "cd && git add .rnd/ → exit 2" 2
assert_stderr_contains "cd && git add .rnd/ → BLOCKED" "BLOCKED"

# git push main after && should be blocked via full-command git guard
run_hook "$(payload 'npm install && git push origin main')"
assert_exit   "npm && git push main → exit 2" 2
assert_stderr_contains "npm && git push main → BLOCKED" "BLOCKED"

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
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
