#!/usr/bin/env bash
# hooks/setup.sh — Reports plugin validation status and jq availability.
# Always exits 0 — status reporter, not a gate.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run validation script and capture pass/fail counts.
_run_validation() {
  local validate_sh="${PLUGIN_ROOT}/lib/validate.sh"
  local val_out pass_count fail_count val_status

  if [[ -x "$validate_sh" ]]; then
    val_out="$("$validate_sh" 2>&1 || true)"
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

  printf '%s %s %s' "$val_status" "$pass_count" "$fail_count"
}

_check_jq() {
  local jq_ver
  if jq_ver="$(jq --version 2>/dev/null)"; then
    printf 'available (%s)' "$jq_ver"
  else
    printf 'not found'
  fi
}

# _run_validation outputs exactly 3 tokens: "<status> <pass_count> <fail_count>"
val_result="$(_run_validation)"
val_status="${val_result%% *}"
rest="${val_result#* }"
pass_count="${rest%% *}"
fail_count="${rest##* }"
jq_status="$(_check_jq)"

ctx="rnd-framework setup:
  Validation: ${val_status} (${pass_count} pass, ${fail_count} fail)
  jq: ${jq_status}"

printf '%s\n' "$(jq -cn --arg ctx "$ctx" \
  '{"hookSpecificOutput":{"hookEventName":"Setup","additionalContext":$ctx}}')"

exit 0
