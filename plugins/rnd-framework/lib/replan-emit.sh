#!/usr/bin/env bash
# replan-emit.sh — Append replan lifecycle events to $RND_DIR/audit.jsonl.
#
# Usage:
#   replan-emit.sh started <iteration> <archive_path>
#   replan-emit.sh diff_emitted <task_changes_count> <assertion_changes_count>
#
# Subcommands:
#   started         Emitted when a replan cycle begins and prior artifacts are archived.
#   diff_emitted    Emitted after the differ writes its replan-diff.md output.
#
# Emitted JSON shapes:
#   started:
#     {event: "replan_started", iteration, archived_to, timestamp}
#
#   diff_emitted:
#     {event: "replan_diff_emitted", task_changes_count, assertion_changes_count, timestamp}
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Event appended (or silently skipped on write failure).
#   1  Missing argument, unknown subcommand, or RND_DIR unset.

set -euo pipefail

if [[ $# -lt 3 ]]; then
  printf 'Usage: replan-emit.sh started <iteration> <archive_path>\n' >&2
  printf '       replan-emit.sh diff_emitted <task_changes_count> <assertion_changes_count>\n' >&2
  exit 1
fi

subcommand="$1"

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'replan-emit.sh: RND_DIR is not set\n' >&2
  exit 1
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

case "$subcommand" in
  started)
    iteration="$2"
    archive_path="$3"

    if ! [[ "$iteration" =~ ^[0-9]+$ ]]; then
      printf 'replan-emit.sh: iteration must be a non-negative integer (got %s)\n' "$iteration" >&2
      exit 1
    fi

    jq -nc \
      --argjson iteration "$iteration" \
      --arg archived_to "$archive_path" \
      --arg ts "$ts" \
      '{
         event: "replan_started",
         iteration: $iteration,
         archived_to: $archived_to,
         timestamp: $ts
       }' \
      >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
    ;;

  diff_emitted)
    task_changes_count="$2"
    assertion_changes_count="$3"

    if ! [[ "$task_changes_count" =~ ^[0-9]+$ ]]; then
      printf 'replan-emit.sh: task_changes_count must be a non-negative integer (got %s)\n' "$task_changes_count" >&2
      exit 1
    fi
    if ! [[ "$assertion_changes_count" =~ ^[0-9]+$ ]]; then
      printf 'replan-emit.sh: assertion_changes_count must be a non-negative integer (got %s)\n' "$assertion_changes_count" >&2
      exit 1
    fi

    jq -nc \
      --argjson task_changes_count "$task_changes_count" \
      --argjson assertion_changes_count "$assertion_changes_count" \
      --arg ts "$ts" \
      '{
         event: "replan_diff_emitted",
         task_changes_count: $task_changes_count,
         assertion_changes_count: $assertion_changes_count,
         timestamp: $ts
       }' \
      >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
    ;;

  *)
    printf 'replan-emit.sh: unknown subcommand: %s\n' "$subcommand" >&2
    exit 1
    ;;
esac
