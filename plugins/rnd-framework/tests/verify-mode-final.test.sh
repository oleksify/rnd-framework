#!/usr/bin/env bash
# tests/verify-mode-final.test.sh — Smoke tests for the --verify-mode=final
# deferral helper and the orchestrator dispatch changes in commands/rnd-start.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

HELPER="${PLUGIN_ROOT}/lib/verify-mode-final-queue.sh"
ORCHESTRATOR="${PLUGIN_ROOT}/commands/rnd-start.md"

TMP_DIR="$(mktemp -d)"
RND_DIR="${TMP_DIR}/rnd"
mkdir -p "${RND_DIR}"
export RND_DIR

trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Helper: queue entry is appended on invocation
# ---------------------------------------------------------------------------

printf '\n--- verify-mode-final-queue: queue entry appended ---\n'

HELPER_EXIT=0
bash "$HELPER" 1 T1 2>/dev/null || HELPER_EXIT=$?
assert_eq "helper exits 0" "0" "$HELPER_EXIT"

QUEUE_FILE="${RND_DIR}/.verify-final-queue.jsonl"
assert_eq "queue file exists after invocation" "0" "$(test -f "$QUEUE_FILE" && echo 0 || echo 1)"

QUEUE_COUNT="$(wc -l < "$QUEUE_FILE" | tr -d ' ')"
assert_eq "queue file has exactly one entry" "1" "$QUEUE_COUNT"

WAVE_VAL="$(jq -r '.wave' "$QUEUE_FILE")"
assert_eq "queue entry has wave=1" "1" "$WAVE_VAL"

TASK_VAL="$(jq -r '.task_id' "$QUEUE_FILE")"
assert_eq "queue entry has task_id=T1" "T1" "$TASK_VAL"

HAS_QUEUED_AT="$(jq 'has("queued_at")' "$QUEUE_FILE")"
assert_eq "queue entry has queued_at field" "true" "$HAS_QUEUED_AT"

# ---------------------------------------------------------------------------
# Helper: audit event is emitted
# ---------------------------------------------------------------------------

printf '\n--- verify-mode-final-queue: audit event emitted ---\n'

AUDIT_FILE="${RND_DIR}/audit.jsonl"
assert_eq "audit.jsonl exists after invocation" "0" "$(test -f "$AUDIT_FILE" && echo 0 || echo 1)"

AUDIT_LINE="$(grep '"event":"verifier_spawn_avoided"' "$AUDIT_FILE" | head -1)"
assert_eq "verifier_spawn_avoided event is present" "0" "$(test -n "$AUDIT_LINE" && echo 0 || echo 1)"

AUDIT_TOOL="$(grep '"event":"verifier_spawn_avoided"' "$AUDIT_FILE" | jq -r '.tool' | head -1)"
assert_eq "audit event tool field is final_mode" "final_mode" "$AUDIT_TOOL"

AUDIT_TASK="$(grep '"event":"verifier_spawn_avoided"' "$AUDIT_FILE" | jq -r '.task_id' | head -1)"
assert_eq "audit event task_id is T1" "T1" "$AUDIT_TASK"

# ---------------------------------------------------------------------------
# Helper: multiple invocations append multiple entries (not overwrite)
# ---------------------------------------------------------------------------

printf '\n--- verify-mode-final-queue: accumulates entries ---\n'

bash "$HELPER" 2 T2 2>/dev/null
QUEUE_COUNT="$(wc -l < "$QUEUE_FILE" | tr -d ' ')"
assert_eq "second invocation appends (2 total entries)" "2" "$QUEUE_COUNT"

SECOND_WAVE="$(jq -r '.wave' "$QUEUE_FILE" | tail -1)"
assert_eq "second entry has wave=2" "2" "$SECOND_WAVE"

SECOND_TASK="$(jq -r '.task_id' "$QUEUE_FILE" | tail -1)"
assert_eq "second entry has task_id=T2" "T2" "$SECOND_TASK"

# ---------------------------------------------------------------------------
# Helper: missing RND_DIR exits 1
# ---------------------------------------------------------------------------

printf '\n--- verify-mode-final-queue: missing RND_DIR exits 1 ---\n'

MISSING_EXIT=0
env -u RND_DIR bash "$HELPER" 1 T99 2>/dev/null || MISSING_EXIT=$?
assert_eq "missing RND_DIR exits 1" "1" "$MISSING_EXIT"

# ---------------------------------------------------------------------------
# Helper: wrong argument count exits 1
# ---------------------------------------------------------------------------

printf '\n--- verify-mode-final-queue: wrong arg count exits 1 ---\n'

BADARGS_EXIT=0
bash "$HELPER" 2>/dev/null || BADARGS_EXIT=$?
assert_eq "no args exits 1" "1" "$BADARGS_EXIT"

BADARGS_EXIT=0
bash "$HELPER" 1 2>/dev/null || BADARGS_EXIT=$?
assert_eq "one arg exits 1" "1" "$BADARGS_EXIT"

# ---------------------------------------------------------------------------
# Orchestrator: flag parsing block is present in rnd-start.md
# ---------------------------------------------------------------------------

printf '\n--- rnd-start.md: flag parsing present ---\n'

assert_eq "flag parsing references appear in rnd-start.md (>=2)" "0" \
  "$(grep -qE 'RND_VERIFY_MODE_FINAL' "$ORCHESTRATOR" && grep -qE '\-\-verify-mode=final' "$ORCHESTRATOR" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# Orchestrator: deferral helper invocation is referenced
# ---------------------------------------------------------------------------

printf '\n--- rnd-start.md: deferral helper invocation present ---\n'

assert_eq "verify-mode-final-queue.sh referenced in rnd-start.md" "0" \
  "$(grep -q 'verify-mode-final-queue.sh' "$ORCHESTRATOR" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# Orchestrator: post-final-wave drain instruction is present
# ---------------------------------------------------------------------------

printf '\n--- rnd-start.md: drain instruction present ---\n'

assert_eq "drain queue instruction appears in rnd-start.md" "0" \
  "$(grep -qE 'drain.*queue|final.*wave.*verifier|\.verify-final-queue' "$ORCHESTRATOR" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# Orchestrator: default per-wave Verifier spawn block still present
# ---------------------------------------------------------------------------

printf '\n--- rnd-start.md: default Verifier spawn path preserved ---\n'

VERIFIER_SPAWN="$(grep -c 'rnd-framework:rnd-verifier' "$ORCHESTRATOR" || echo 0)"
assert_eq "rnd-verifier spawn still referenced in rnd-start.md" "0" \
  "$(test "$VERIFIER_SPAWN" -ge 1 && echo 0 || echo 1)"

report
