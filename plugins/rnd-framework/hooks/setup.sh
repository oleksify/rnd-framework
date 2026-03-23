#!/usr/bin/env bash
# hooks/setup.sh — Reports plugin validation status and jq availability.
# Always exits 0 — status reporter, not a gate.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run validation script and capture pass/fail counts.
validate_sh="${PLUGIN_ROOT}/lib/validate.sh"
validate_ts="${PLUGIN_ROOT}/lib/validate.ts"

if [[ -x "$validate_sh" ]]; then
  val_out="$("$validate_sh" 2>&1 || true)"
elif [[ -f "$validate_ts" ]]; then
  val_out="$(bun "$validate_ts" 2>&1 || true)"
else
  val_out="(no validation script found)"
fi

pass_count="$(printf '%s' "$val_out" | grep -c '  PASS  ' 2>/dev/null || true)"
fail_count="$(printf '%s' "$val_out" | grep -c '  FAIL  ' 2>/dev/null || true)"
[[ "$pass_count" =~ ^[0-9]+$ ]] || pass_count=0
[[ "$fail_count" =~ ^[0-9]+$ ]] || fail_count=0
if (( fail_count > 0 )); then
  val_status="fail"
else
  val_status="pass"
fi

# Check jq availability.
if jq_ver="$(jq --version 2>/dev/null)"; then
  jq_status="available (${jq_ver})"
else
  jq_status="not found"
fi

ctx="rnd-framework setup:
  Validation: ${val_status} (${pass_count} pass, ${fail_count} fail)
  jq: ${jq_status}"

printf '%s\n' "$(jq -cn --arg ctx "$ctx" \
  '{"hookSpecificOutput":{"hookEventName":"Setup","additionalContext":$ctx}}')"

exit 0
