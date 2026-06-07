#!/usr/bin/env bash
# scope-emit.sh — Append a scope_locked event to $RND_DIR/audit.jsonl.
#
# Usage:
#   scope-emit.sh "<deliverable_ids_csv>" "<n_deliverables>"
#
# Arguments:
#   deliverable_ids_csv  Comma-separated deliverable IDs (e.g. "D1,D2,D3").
#   n_deliverables       Integer count of deliverables.
#
# Emitted JSON shape:
#   {event, n_deliverables, deliverable_ids, timestamp}
#   where n_deliverables is passed as an arg (mirroring how premortem-emit
#   passes failure_mode_count) and deliverable_ids is the split array.
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Event appended (or silently skipped on write failure).
#   1  Missing argument or RND_DIR unset.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  printf 'Usage: scope-emit.sh "<deliverable_ids_csv>" "<n_deliverables>"\n' >&2
  exit 1
fi

deliverable_ids_csv="$1"
n_deliverables="$2"

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'scope-emit.sh: RND_DIR is not set\n' >&2
  exit 1
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq -nc \
  --arg deliverable_ids_csv "$deliverable_ids_csv" \
  --arg ts "$ts" \
  --argjson n_deliverables "$n_deliverables" \
  '($deliverable_ids_csv | split(",")) as $deliverable_ids |
   {
     event: "scope_locked",
     n_deliverables: $n_deliverables,
     deliverable_ids: $deliverable_ids,
     timestamp: $ts
   }' \
  >> "${RND_DIR}/audit.jsonl" 2>/dev/null || true
