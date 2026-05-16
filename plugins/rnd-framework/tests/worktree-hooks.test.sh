#!/usr/bin/env bash
# tests/worktree-hooks.test.sh — Lifecycle tests for the worktree hooks.
#
# Exercises:
#   - hooks/worktree-create.sh emits a worktree_created audit event.
#   - hooks/worktree-remove.sh emits a worktree_removed audit event.
#   - hooks/session-end.sh sweeps orphan worktrees whose path contains
#     `.rnd-worktrees/`.
#
# The test scaffolds a throwaway git repo in mktemp -d, pins git author
# env vars so the seed commit succeeds on any developer machine, and
# tears the whole tree down on EXIT.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CREATE_HOOK="${PLUGIN_ROOT}/hooks/worktree-create.sh"
REMOVE_HOOK="${PLUGIN_ROOT}/hooks/worktree-remove.sh"
END_HOOK="${PLUGIN_ROOT}/hooks/session-end.sh"

# ---------------------------------------------------------------------------
# Scaffold throwaway git repo + RND_DIR
# ---------------------------------------------------------------------------

tmp="$(mktemp -d)"

cleanup() {
  # Remove any worktrees we may have added before nuking the tree, so git
  # doesn't leave dangling administrative entries in the source repo's
  # .git/worktrees directory on subsequent runs.
  if [[ -d "${tmp}/repo/.git" ]]; then
    git -C "${tmp}/repo" worktree prune 2>/dev/null || true
  fi

  rm -rf "$tmp"
}
trap cleanup EXIT

repo="${tmp}/repo"
mkdir -p "$repo"

git -C "$repo" init -q

GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@test \
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@test \
  git -C "$repo" commit --allow-empty -q -m seed

# RND_DIR lives under the repo so cleanup covers it too.
export RND_DIR="${repo}/.rnd/session-test"
mkdir -p "$RND_DIR"

# ---------------------------------------------------------------------------
# Test 1 — worktree-create.sh echoes a path and emits worktree_created
#
# Mirrors the real Claude Code stdin contract (v2.1.83+): the harness sends
# {session_id, transcript_path, cwd, hook_event_name, name}. The hook must
# echo the chosen worktree path to stdout — absence of a path on stdout
# aborts the agent spawn.
# ---------------------------------------------------------------------------

create_json="$(printf '{"session_id":"sid1","transcript_path":"/tmp/t.jsonl","cwd":"%s","hook_event_name":"WorktreeCreate","name":"agent-deadbeef"}' "$repo")"
run_hook "$CREATE_HOOK" "$create_json"

assert_exit_code "worktree-create.sh exits 0" 0

expected_session="$(basename "$RND_DIR")"
expected_wt="${repo}/.rnd-worktrees/${expected_session}/agent-deadbeef"

assert_eq "worktree-create.sh echoes computed path to stdout" \
  "$expected_wt" \
  "$HOOK_STDOUT"

audit_log="${RND_DIR}/audit.jsonl"

if [[ -f "$audit_log" ]]; then
  audit_contents="$(cat "$audit_log")"
else
  audit_contents=""
fi

assert_contains "audit.jsonl gains worktree_created event" \
  '"event":"worktree_created"' \
  "$audit_contents"

# ---------------------------------------------------------------------------
# Test 2 — worktree-remove.sh emits worktree_removed
# ---------------------------------------------------------------------------

remove_json="$(printf '{"session_id":"sid1","transcript_path":"/tmp/t.jsonl","cwd":"%s","hook_event_name":"WorktreeRemove","name":"agent-deadbeef","tool_input":{"path":"%s"}}' "$repo" "$expected_wt")"
run_hook "$REMOVE_HOOK" "$remove_json"

assert_exit_code "worktree-remove.sh exits 0" 0

audit_contents="$(cat "$audit_log")"

assert_contains "audit.jsonl gains worktree_removed event" \
  '"event":"worktree_removed"' \
  "$audit_contents"

# ---------------------------------------------------------------------------
# Test 3 — session-end.sh sweeps orphan .rnd-worktrees/* worktrees
# ---------------------------------------------------------------------------

# Add a real fake-rnd-owned worktree. The path segment `.rnd-worktrees/`
# is what session-end.sh keys on.
orphan_path="${repo}/.rnd-worktrees/sid1/T1"
mkdir -p "$(dirname "$orphan_path")"

GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@test \
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@test \
  git -C "$repo" worktree add -q -b orphan-branch "$orphan_path" >/dev/null

before_list="$(git -C "$repo" worktree list --porcelain)"

assert_contains "fake orphan worktree is registered before sweep" \
  ".rnd-worktrees/sid1/T1" \
  "$before_list"

# session-end.sh detects the orphan by inspecting `git worktree list` in the
# current working directory. The hook is git-cwd based, not RND_DIR based,
# so we invoke it from inside the seed repo.
(
  cd "$repo"
  HOOK_EXIT=0
  "$END_HOOK" >/dev/null 2>&1 < /dev/null || HOOK_EXIT=$?
  exit "$HOOK_EXIT"
)
end_exit=$?

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ "$end_exit" -eq 0 ]]; then
  printf '  PASS  session-end.sh exits 0\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  session-end.sh exits 0 (got %d)\n' "$end_exit"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

after_list="$(git -C "$repo" worktree list --porcelain)"

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ "$after_list" != *".rnd-worktrees/sid1/T1"* ]]; then
  printf '  PASS  orphan worktree is swept by session-end.sh\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  orphan worktree is swept by session-end.sh\n'
  printf '        worktree list still contains the orphan:\n%s\n' "$after_list"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

report
