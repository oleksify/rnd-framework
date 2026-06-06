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

printf '\n--- bash-gate: additional blocked patterns ---\n'

# git checkout -- . (period as explicit path): must block
run_hook "$BASH_GATE" "$(_make_json 'git checkout -- .')"
assert_exit_code "git checkout -- . is blocked (exit 2)" 2
assert_contains "git checkout -- . stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git reset --hard (bare, no ref): must block
run_hook "$BASH_GATE" "$(_make_json 'git reset --hard')"
assert_exit_code "git reset --hard (bare) is blocked (exit 2)" 2
assert_contains "git reset --hard (bare) stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git clean -f -d (separate flag tokens): must block
run_hook "$BASH_GATE" "$(_make_json 'git clean -f -d')"
assert_exit_code "git clean -f -d (separate flags) is blocked (exit 2)" 2
assert_contains "git clean -f -d stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git clean -fx (-f and -x, no -d): must block
run_hook "$BASH_GATE" "$(_make_json 'git clean -fx')"
assert_exit_code "git clean -fx is blocked (exit 2)" 2
assert_contains "git clean -fx stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git stash drop stash@{0}: must block
run_hook "$BASH_GATE" "$(_make_json 'git stash drop stash@{0}')"
assert_exit_code "git stash drop stash@{0} is blocked (exit 2)" 2
assert_contains "git stash drop stash@{0} stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

# git checkout -- src/main.ts (nested path): must block
run_hook "$BASH_GATE" "$(_make_json 'git checkout -- src/main.ts')"
assert_exit_code "git checkout -- src/main.ts is blocked (exit 2)" 2
assert_contains "git checkout -- src/main.ts stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

printf '\n--- bash-gate: additional allowed operations ---\n'

# git checkout main (branch switch, not file discard): must pass
run_hook "$BASH_GATE" "$(_make_json 'git checkout main')"
assert_exit_code "git checkout main (branch switch) is allowed (exit 0)" 0

# git reset --soft HEAD~1 (non-destructive reset): must pass
run_hook "$BASH_GATE" "$(_make_json 'git reset --soft HEAD~1')"
assert_exit_code "git reset --soft is allowed (exit 0)" 0

# git clean -f (force alone, no d/x flag): must pass
run_hook "$BASH_GATE" "$(_make_json 'git clean -f')"
assert_exit_code "git clean -f (no d/x) is allowed (exit 0)" 0

# git worktree remove /path (without --force): must pass
run_hook "$BASH_GATE" "$(_make_json 'git worktree remove /some/worktree')"
assert_exit_code "git worktree remove (no --force) is allowed (exit 0)" 0

# git stash list: must pass
run_hook "$BASH_GATE" "$(_make_json 'git stash list')"
assert_exit_code "git stash list is allowed (exit 0)" 0

printf '\n--- bash-gate: global git options do not bypass destructive blocks ---\n'

# A global option (-C <path>, -c k=v, --git-dir=...) placed before the subcommand
# must not let a destructive op slip past the denylist.
run_hook "$BASH_GATE" "$(_make_json 'git -C /repo reset --hard HEAD')"
assert_exit_code "git -C <path> reset --hard is blocked (exit 2)" 2
assert_contains "git -C reset --hard stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

run_hook "$BASH_GATE" "$(_make_json 'git -c core.pager=cat clean -fd')"
assert_exit_code "git -c k=v clean -fd is blocked (exit 2)" 2
assert_contains "git -c clean -fd stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

run_hook "$BASH_GATE" "$(_make_json 'git --git-dir=/repo/.git branch -D feature')"
assert_exit_code "git --git-dir=... branch -D is blocked (exit 2)" 2
assert_contains "git --git-dir branch -D stderr contains BLOCKED" "BLOCKED" "$HOOK_STDERR"

run_hook "$BASH_GATE" "$(_make_json 'git --no-pager checkout .')"
assert_exit_code "git --no-pager checkout . is blocked (exit 2)" 2

# Control: a global option on a SAFE git op must still pass through.
run_hook "$BASH_GATE" "$(_make_json 'git -C /repo status')"
assert_exit_code "git -C <path> status is allowed (exit 0)" 0

run_hook "$BASH_GATE" "$(_make_json 'git -C /repo log --oneline -5')"
assert_exit_code "git -C <path> log is allowed (exit 0)" 0

printf '\n--- bash-gate: audit event emission on block ---\n'

# Verify that blocking a destructive git op writes a gate_fired entry to audit.jsonl.
# Requires RND_DIR to be set so audit-event.sh has a write target.
_tmp_rnd="$(mktemp -d)"
_audit_file="${_tmp_rnd}/audit.jsonl"

RND_DIR="$_tmp_rnd" run_hook "$BASH_GATE" "$(_make_json 'git reset --hard HEAD')"
assert_exit_code "git reset --hard is blocked when RND_DIR is set (exit 2)" 2

if [[ -f "$_audit_file" ]]; then
  _audit_line="$(grep '"gate_fired"' "$_audit_file" | tail -1)"
  assert_contains "audit.jsonl contains gate_fired event" '"gate_fired"' "$_audit_line"
  assert_contains "audit.jsonl contains destructive_git_blocked with per-op discriminator" '"destructive_git_blocked:' "$_audit_line"
else
  assert_eq "audit.jsonl exists after blocked git reset --hard" "exists" "missing"
fi

RND_DIR="$_tmp_rnd" run_hook "$BASH_GATE" "$(_make_json 'git checkout .')"
assert_exit_code "git checkout . is blocked when RND_DIR is set (exit 2)" 2
_audit_count="$(grep -c '"gate_fired"' "$_audit_file" 2>/dev/null || printf '0')"
assert_contains "audit.jsonl accumulates multiple gate_fired events" "2" "$_audit_count"

RND_DIR="$_tmp_rnd" run_hook "$BASH_GATE" "$(_make_json 'git branch -D old-branch')"
assert_exit_code "git branch -D is blocked when RND_DIR is set (exit 2)" 2
RND_DIR="$_tmp_rnd" run_hook "$BASH_GATE" "$(_make_json 'git stash clear')"
assert_exit_code "git stash clear is blocked when RND_DIR is set (exit 2)" 2
RND_DIR="$_tmp_rnd" run_hook "$BASH_GATE" "$(_make_json 'git worktree remove --force /tmp/wt')"
assert_exit_code "git worktree remove --force is blocked when RND_DIR is set (exit 2)" 2
RND_DIR="$_tmp_rnd" run_hook "$BASH_GATE" "$(_make_json 'git clean -fd .')"
assert_exit_code "git clean -fd is blocked when RND_DIR is set (exit 2)" 2

_total_audit_count="$(grep -c '"gate_fired"' "$_audit_file" 2>/dev/null || printf '0')"
assert_contains "audit.jsonl has all 6 gate_fired events" "6" "$_total_audit_count"

rm -rf "$_tmp_rnd"

report
