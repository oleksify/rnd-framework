#!/usr/bin/env bash
# tests/bash-gate-destructive-git.test.sh — Tests for destructive git command denylist.
# Verifies that bash-gate.sh blocks destructive git operations and allows safe ones.
# Usage: bash tests/bash-gate-destructive-git.test.sh
# Exits 0 if all tests pass, 1 if any fail.
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

printf '\n--- bash-gate: destructive git denylist (blocked patterns) ---\n'

# git reset --hard: must block with BLOCKED and rnd-undo in stderr
run_hook "$BASH_GATE" "$(_make_json 'git reset --hard HEAD~1')"
assert_exit_code "git reset --hard is blocked (exit 2)" 2
assert_contains "git reset --hard stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"
assert_contains "git reset --hard stderr contains rnd-undo" "rnd-undo" "$HOOK_STDERR"

# git checkout .: must block
run_hook "$BASH_GATE" "$(_make_json 'git checkout .')"
assert_exit_code "git checkout . is blocked (exit 2)" 2
assert_contains "git checkout . stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"
assert_contains "git checkout . stderr contains rnd-undo" "rnd-undo" "$HOOK_STDERR"

# git checkout -- <path>: must block
run_hook "$BASH_GATE" "$(_make_json 'git checkout -- foo.txt')"
assert_exit_code "git checkout -- <path> is blocked (exit 2)" 2
assert_contains "git checkout -- <path> stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git clean -fd: must block
run_hook "$BASH_GATE" "$(_make_json 'git clean -fd')"
assert_exit_code "git clean -fd is blocked (exit 2)" 2
assert_contains "git clean -fd stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git clean -fdx: must block
run_hook "$BASH_GATE" "$(_make_json 'git clean -fdx')"
assert_exit_code "git clean -fdx is blocked (exit 2)" 2
assert_contains "git clean -fdx stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git stash drop: must block
run_hook "$BASH_GATE" "$(_make_json 'git stash drop')"
assert_exit_code "git stash drop is blocked (exit 2)" 2
assert_contains "git stash drop stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git stash clear: must block
run_hook "$BASH_GATE" "$(_make_json 'git stash clear')"
assert_exit_code "git stash clear is blocked (exit 2)" 2
assert_contains "git stash clear stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git reflog expire: must block
run_hook "$BASH_GATE" "$(_make_json 'git reflog expire --expire=now --all')"
assert_exit_code "git reflog expire is blocked (exit 2)" 2
assert_contains "git reflog expire stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git branch -D: must block
run_hook "$BASH_GATE" "$(_make_json 'git branch -D feature-xyz')"
assert_exit_code "git branch -D is blocked (exit 2)" 2
assert_contains "git branch -D stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git worktree remove --force: must block
run_hook "$BASH_GATE" "$(_make_json 'git worktree remove --force /some/path')"
assert_exit_code "git worktree remove --force is blocked (exit 2)" 2
assert_contains "git worktree remove --force stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

printf '\n--- bash-gate: safe git operations (allowed sentinels) ---\n'

# git status: must pass through
run_hook "$BASH_GATE" "$(_make_json 'git status')"
assert_exit_code "git status is allowed (exit 0)" 0

# git log: must pass through
run_hook "$BASH_GATE" "$(_make_json 'git log --oneline -5')"
assert_exit_code "git log is allowed (exit 0)" 0

# git diff: must pass through
run_hook "$BASH_GATE" "$(_make_json 'git diff HEAD')"
assert_exit_code "git diff is allowed (exit 0)" 0

# git add <file> (non-.rnd/ path): must pass through
run_hook "$BASH_GATE" "$(_make_json 'git add src/foo.txt')"
assert_exit_code "git add <file> is allowed (exit 0)" 0

# git commit: must pass through
run_hook "$BASH_GATE" "$(_make_json 'git commit -m "fix: update handler"')"
assert_exit_code "git commit is allowed (exit 0)" 0

# git clean -n (dry-run, not destructive): must pass through
run_hook "$BASH_GATE" "$(_make_json 'git clean -n')"
assert_exit_code "git clean -n (dry-run) is allowed (exit 0)" 0

# git stash push (safe stash operation): must pass through
run_hook "$BASH_GATE" "$(_make_json 'git stash push -m my-stash')"
assert_exit_code "git stash push is allowed (exit 0)" 0

# git reflog (without expire): must pass through
run_hook "$BASH_GATE" "$(_make_json 'git reflog show')"
assert_exit_code "git reflog (no expire) is allowed (exit 0)" 0

# git branch -d (lowercase, safe delete): must pass through
run_hook "$BASH_GATE" "$(_make_json 'git branch -d merged-feature')"
assert_exit_code "git branch -d (lowercase) is allowed (exit 0)" 0

report
