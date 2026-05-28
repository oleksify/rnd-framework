#!/usr/bin/env bash
# outside-view-emit.sh — Append an outside_view_injected event to $RND_DIR/audit.jsonl.
#
# Usage:
#   outside-view-emit.sh "<mode>" "<n_total>" "<shapes_json>" "<framing_constraint_emitted>"
#
# Arguments:
#   mode                       Corpus mode label (e.g. "thin-corpus", "full-corpus").
#   n_total                    Integer count of shapes injected.
#   shapes_json                JSON array of shape objects (e.g. '[{"shape":"crud","task_count":2,"fail_count":0}]').
#   framing_constraint_emitted Boolean (true|false) — whether a framing constraint was emitted.
#
# Emitted JSON shape:
#   {event, mode, n_total, shapes, framing_constraint_emitted, timestamp}
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Event appended (or silently skipped on write failure).
#   1  Missing argument or RND_DIR unset.

set -euo pipefail

if [[ $# -lt 4 ]]; then
  printf 'Usage: outside-view-emit.sh "<mode>" "<n_total>" "<shapes_json>" "<framing_constraint_emitted>"\n' >&2
  exit 1
fi

mode="$1"
n_total="$2"
shapes_json="$3"
framing_constraint_emitted="$4"

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'outside-view-emit.sh: RND_DIR is not set\n' >&2
  exit 1
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -nc \
  --arg mode "$mode" \
  --argjson n_total "$n_total" \
  --argjson shapes "$shapes_json" \
  --argjson framing_constraint_emitted "$framing_constraint_emitted" \
  --arg ts "$ts" \
  '{
     event: "outside_view_injected",
     mode: $mode,
     n_total: $n_total,
     shapes: $shapes,
     framing_constraint_emitted: $framing_constraint_emitted,
     timestamp: $ts
   }' \
  >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
