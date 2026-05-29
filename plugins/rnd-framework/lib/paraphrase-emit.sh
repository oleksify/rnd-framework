#!/usr/bin/env bash
# paraphrase-emit.sh — Append a paraphrase_injected event to $RND_DIR/audit.jsonl.
#
# Usage:
#   paraphrase-emit.sh <n_assertions>
#
# Arguments:
#   n_assertions  Integer count of assertions paraphrased and injected.
#
# Emitted JSON shape:
#   {event: "paraphrase_injected", n_assertions, timestamp}
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Event appended (or silently skipped on write failure).
#   1  Missing argument, non-integer argument, or RND_DIR unset.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  printf 'Usage: paraphrase-emit.sh <n_assertions>\n' >&2
  exit 1
fi

n_assertions="$1"

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'paraphrase-emit.sh: RND_DIR is not set\n' >&2
  exit 1
fi

if ! [[ "$n_assertions" =~ ^[0-9]+$ ]]; then
  printf 'paraphrase-emit.sh: n_assertions must be a non-negative integer (got %s)\n' "$n_assertions" >&2
  exit 1
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -nc \
  --argjson n_assertions "$n_assertions" \
  --arg ts "$ts" \
  '{
     event: "paraphrase_injected",
     n_assertions: $n_assertions,
     timestamp: $ts
   }' \
  >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
