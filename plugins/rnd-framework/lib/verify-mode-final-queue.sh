#!/usr/bin/env bash
# verify-mode-final-queue.sh — Append a deferred verifier entry to the
# final-mode queue and emit a verifier_spawn_avoided audit event.
#
# Usage:
#   verify-mode-final-queue.sh <wave> <task_id>
#
# Appends one JSON line to $RND_DIR/.verify-final-queue.jsonl:
#   {"wave":<N>,"task_id":"T<id>","queued_at":"<ISO timestamp>"}
#
# Also emits a verifier_spawn_avoided audit event with reason "final_mode".
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Entry queued and audit event emitted.
#   1  Missing argument or RND_DIR unset.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 2 ]]; then
  printf 'Usage: verify-mode-final-queue.sh <wave> <task_id>\n' >&2
  exit 1
fi

_WAVE="$1"
_TASK_ID="$2"

if [[ ! "$_WAVE" =~ ^[0-9]+$ ]]; then
  printf 'verify-mode-final-queue.sh: wave must be numeric, got %q\n' "$_WAVE" >&2
  exit 1
fi

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'verify-mode-final-queue.sh: RND_DIR is not set\n' >&2
  exit 1
fi

_QUEUE_FILE="${RND_DIR}/.verify-final-queue.jsonl"
_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Emit audit event BEFORE the queue write so a queue-write failure leaves
# the orchestrator with a consistent record (audit says "we deferred this"
# only after we know the queue write will be attempted).
RND_DIR="$RND_DIR" bash "${_SCRIPT_DIR}/audit-event.sh" \
  "verifier_spawn_avoided" "$_TASK_ID" "final_mode"

jq -nc \
  --argjson wave "$_WAVE" \
  --arg task_id "$_TASK_ID" \
  --arg queued_at "$_TS" \
  '{"wave":$wave,"task_id":$task_id,"queued_at":$queued_at}' \
  >> "$_QUEUE_FILE"
