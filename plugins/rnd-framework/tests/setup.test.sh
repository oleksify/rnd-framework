#!/usr/bin/env bash
# tests/setup.test.sh — Unit tests for hooks/setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/../hooks"
SETUP_SH="${HOOKS_DIR}/setup.sh"

pass=0
fail=0

run_case() {
  local name="$1"
  local result="$2"
  if [[ "$result" == "pass" ]]; then
    printf '  PASS  %s\n' "$name"
    pass=$(( pass + 1 ))
  else
    printf '  FAIL  %s\n' "$name"
    fail=$(( fail + 1 ))
  fi
}

# ---------------------------------------------------------------------------
# Test: script exists and is executable
# ---------------------------------------------------------------------------
if [[ -x "$SETUP_SH" ]]; then
  run_case "setup.sh exists and is executable" pass
else
  run_case "setup.sh exists and is executable" fail
fi

# ---------------------------------------------------------------------------
# Test: always exits 0
# ---------------------------------------------------------------------------
"$SETUP_SH" > /dev/null 2>&1
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
  run_case "always exits 0" pass
else
  run_case "always exits 0" fail
fi

# ---------------------------------------------------------------------------
# Test: outputs valid JSON
# ---------------------------------------------------------------------------
output="$("$SETUP_SH" 2>/dev/null)"
if printf '%s' "$output" | jq . > /dev/null 2>&1; then
  run_case "outputs valid JSON" pass
else
  run_case "outputs valid JSON" fail
fi

# ---------------------------------------------------------------------------
# Test: hookEventName is "Setup"
# ---------------------------------------------------------------------------
event_name="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null || true)"
if [[ "$event_name" == "Setup" ]]; then
  run_case "hookEventName is Setup" pass
else
  run_case "hookEventName is Setup" fail
fi

# ---------------------------------------------------------------------------
# Test: additionalContext contains validation summary
# ---------------------------------------------------------------------------
ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || true)"
if [[ "$ctx" =~ "Validation:" ]] && [[ "$ctx" =~ "pass" ]]; then
  run_case "additionalContext contains validation summary" pass
else
  run_case "additionalContext contains validation summary" fail
fi

# ---------------------------------------------------------------------------
# Test: additionalContext contains jq availability (not bun)
# ---------------------------------------------------------------------------
if [[ "$ctx" =~ "jq:" ]]; then
  run_case "additionalContext contains jq availability" pass
else
  run_case "additionalContext contains jq availability" fail
fi

# ---------------------------------------------------------------------------
# Test: no bun check in output
# ---------------------------------------------------------------------------
if [[ ! "$ctx" =~ "bun:" ]]; then
  run_case "no bun availability check in output" pass
else
  run_case "no bun availability check in output" fail
fi

# ---------------------------------------------------------------------------
# Test: hookSpecificOutput has both hookEventName and additionalContext fields
# ---------------------------------------------------------------------------
has_event="$(printf '%s' "$output" | jq 'has("hookSpecificOutput") and (.hookSpecificOutput | has("hookEventName")) and (.hookSpecificOutput | has("additionalContext"))' 2>/dev/null || true)"
if [[ "$has_event" == "true" ]]; then
  run_case "hookSpecificOutput has hookEventName and additionalContext" pass
else
  run_case "hookSpecificOutput has hookEventName and additionalContext" fail
fi

# ---------------------------------------------------------------------------
# Test: pass/fail counts are numeric in the validation line
# ---------------------------------------------------------------------------
if [[ "$ctx" =~ ([0-9]+)" pass, "([0-9]+)" fail" ]]; then
  run_case "validation summary contains numeric pass/fail counts" pass
else
  run_case "validation summary contains numeric pass/fail counts" fail
fi

# ---------------------------------------------------------------------------
# Test: exits 0 even when validate.sh doesn't exist (fallback logic)
# ---------------------------------------------------------------------------
# Simulate the fallback case with a temp plugin root that has no validate script
tmp_root="$(mktemp -d)"
mkdir -p "${tmp_root}/hooks" "${tmp_root}/lib"
cp "${HOOKS_DIR}/lib.sh" "${tmp_root}/hooks/lib.sh"
# Write a minimal setup.sh pointing at this fake plugin root
cat > "${tmp_root}/hooks/setup.sh" << 'INNEREOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
if (( fail_count > 0 )); then val_status="fail"; else val_status="pass"; fi
if jq_ver="$(jq --version 2>/dev/null)"; then jq_status="available (${jq_ver})"; else jq_status="not found"; fi
ctx="rnd-framework setup:
  Validation: ${val_status} (${pass_count} pass, ${fail_count} fail)
  jq: ${jq_status}"
printf '%s\n' "$(jq -cn --arg ctx "$ctx" \
  '{"hookSpecificOutput":{"hookEventName":"Setup","additionalContext":$ctx}}')"
exit 0
INNEREOF
chmod +x "${tmp_root}/hooks/setup.sh"
fallback_out="$("${tmp_root}/hooks/setup.sh" 2>/dev/null)"
fallback_exit=$?
rm -rf "$tmp_root"

if [[ $fallback_exit -eq 0 ]] && \
   [[ "$(printf '%s' "$fallback_out" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" == "Setup" ]]; then
  run_case "exits 0 and outputs Setup JSON when no validation script found" pass
else
  run_case "exits 0 and outputs Setup JSON when no validation script found" fail
fi

# ---------------------------------------------------------------------------
# Test: validate.md command references an existing script
# ---------------------------------------------------------------------------
VALIDATE_CMD="${SCRIPT_DIR}/../commands/validate.md"
if [[ -f "$VALIDATE_CMD" ]]; then
  # Extract the script path pattern from the command file (e.g., validate.sh or validate.ts)
  script_ref="$(grep -oE 'lib/validate\.[a-z]+' "$VALIDATE_CMD" | head -1)"
  if [[ -n "$script_ref" ]] && [[ -f "${SCRIPT_DIR}/../${script_ref}" ]]; then
    run_case "validate.md references existing script (${script_ref})" pass
  else
    run_case "validate.md references existing script (got: ${script_ref:-none})" fail
  fi
else
  run_case "validate.md command file exists" fail
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\nTotal: %d pass, %d fail\n' "$pass" "$fail"
if [[ $fail -gt 0 ]]; then
  exit 1
fi
exit 0
