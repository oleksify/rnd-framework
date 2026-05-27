#!/usr/bin/env bash
# premortem-emit.sh — Append a premortem_generated event to $RND_DIR/audit.jsonl.
#
# Usage:
#   premortem-emit.sh "<framings_csv>" "<failure_mode_count>"
#
# Arguments:
#   framings_csv       Comma-separated framing labels (e.g. "scope,cost,timeline").
#   failure_mode_count Integer count of failure modes identified.
#
# Emitted JSON shape:
#   {event, n, framings, failure_mode_count, timestamp}
#   where n == length of the framings array (derived, not passed as an arg).
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Event appended (or silently skipped on write failure).
#   1  Missing argument or RND_DIR unset.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  printf 'Usage: premortem-emit.sh "<framings_csv>" "<failure_mode_count>"\n' >&2
  exit 1
fi

framings_csv="$1"
failure_mode_count="$2"

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'premortem-emit.sh: RND_DIR is not set\n' >&2
  exit 1
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -nc \
  --arg framings_csv "$framings_csv" \
  --arg ts "$ts" \
  --argjson failure_mode_count "$failure_mode_count" \
  '($framings_csv | split(",")) as $framings |
   {
     event: "premortem_generated",
     n: ($framings | length),
     framings: $framings,
     failure_mode_count: $failure_mode_count,
     timestamp: $ts
   }' \
  >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
