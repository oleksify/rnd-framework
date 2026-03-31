#!/usr/bin/env bash
# tests/hooks-rewrite.test.sh — Tests for rewritten complex hooks.
# Usage: bash tests/hooks-rewrite.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="${SCRIPT_DIR}/../hooks"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Shared test infrastructure: a mock session dir + shimmed lib.sh
# ---------------------------------------------------------------------------
# We create a /sessions/ path so active_session_dir's path guard passes.
state_dir="$(mktemp -d)"
sessions_dir="${state_dir}/sessions/20260325-test"
mkdir -p "${sessions_dir}/builds"
printf 'line1\nline2\nline3\nline4\nline5\nline6\n' > "${sessions_dir}/plan.md"
printf 'iter1\niter2\n' > "${sessions_dir}/iteration-log.md"
printf 'content\n' > "${sessions_dir}/builds/T3-manifest.md"
sleep 0.05
printf 'content\n' > "${sessions_dir}/builds/T5-manifest.md"

mock_dir="${state_dir}/mock"
mkdir -p "$mock_dir"

# A lib.sh shim: sources the real lib.sh then overrides session resolution.
cat > "${mock_dir}/lib.sh" << LIBSHIM
source "${HOOKS_DIR}/lib.sh"
resolve_rnd_dir() { printf '%s' "${sessions_dir}"; }
active_session_dir() {
  local dir
  dir="\$(resolve_rnd_dir)"
  [[ -d "\$dir" ]] && printf '%s' "\$dir"
}
LIBSHIM

# Helper: build a wrapper script that sources the shimmed lib, then runs hook body.
# Usage: make_wrapper <source_hook_path> <skip_header_lines> <output_path>
make_wrapper() {
  local hook="$1" skip="$2" out="$3"
  printf '#!/usr/bin/env bash\nMOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nsource "${MOCK_DIR}/lib.sh"\n' > "$out"
  tail -n +"$skip" "$hook" >> "$out"
  chmod +x "$out"
}

trap 'rm -rf "$state_dir"' EXIT

# ---------------------------------------------------------------------------
# session-start.sh tests
# ---------------------------------------------------------------------------
SESSION_START="${HOOKS_DIR}/session-start.sh"

printf '%s\n' '--- session-start.sh ---'

run_hook "$SESSION_START"
assert_exit_code "session-start exits 0" 0

output_json="$HOOK_STDOUT"
if printf '%s' "$output_json" | jq . > /dev/null 2>&1; then
  assert_eq "session-start outputs valid JSON" "pass" "pass"
else
  assert_eq "session-start outputs valid JSON" "pass" "fail"
fi

event_name="$(printf '%s' "$output_json" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null || true)"
assert_eq "session-start hookEventName is SessionStart" "SessionStart" "$event_name"

ctx="$(printf '%s' "$output_json" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"

# Criterion: output does not contain YAML --- delimiters (exact line match)
if printf '%s' "$ctx" | grep -qE '^---$'; then
  assert_eq "session-start strips YAML frontmatter (no --- in output)" "no_dashes" "has_dashes"
else
  assert_eq "session-start strips YAML frontmatter (no --- in output)" "no_dashes" "no_dashes"
fi

# Criterion: additionalContext contains skill content (post-frontmatter body present)
assert_contains "session-start context contains skill content" "rnd-framework" "$ctx"

# Criterion: additionalContext is non-empty
[[ -n "$ctx" ]] \
  && assert_eq "session-start additionalContext is non-empty" "pass" "pass" \
  || assert_eq "session-start additionalContext is non-empty" "pass" "fail"

# Quality: no inline awk for frontmatter stripping in session-start.sh source
if grep -q "BEGIN { in_front=0" "$SESSION_START" 2>/dev/null; then
  assert_eq "session-start does not use inline awk for frontmatter" "no_inline_awk" "has_inline_awk"
else
  assert_eq "session-start does not use inline awk for frontmatter" "no_inline_awk" "no_inline_awk"
fi

# Quality: skill path is stored in a named constant (not bare string literal)
# The old code used: skill_file="${PLUGIN_ROOT}/skills/using-rnd-framework/SKILL.md"
# The new code should use a readonly local constant
if grep -qE 'readonly|local -r' "$SESSION_START" 2>/dev/null; then
  assert_eq "session-start skill path uses a named constant" "pass" "pass"
else
  assert_eq "session-start skill path uses a named constant" "pass" "fail"
fi

# Criterion: version mismatch warning is present when cached and source versions differ.
# Build a fake plugin tree with mismatched versions.
vm_dir="${state_dir}/versiontest"
mkdir -p "${vm_dir}/.claude-plugin" "${vm_dir}/skills/using-rnd-framework" "${vm_dir}/hooks" "${vm_dir}/lib"
cp "${HOOKS_DIR}/lib.sh" "${vm_dir}/hooks/lib.sh"
[[ -f "${SCRIPT_DIR}/../lib/rnd-dir.sh" ]] && cp "${SCRIPT_DIR}/../lib/rnd-dir.sh" "${vm_dir}/lib/rnd-dir.sh" && chmod +x "${vm_dir}/lib/rnd-dir.sh"
printf '{"name":"rnd-framework","version":"0.0.1","description":"test"}\n' > "${vm_dir}/.claude-plugin/plugin.json"
printf -- '---\nname: test-skill\ndescription: test\neffort: low\n---\n\nSkill body text.\n' > "${vm_dir}/skills/using-rnd-framework/SKILL.md"
mkdir -p "${vm_dir}/gitroot/plugins/rnd-framework/.claude-plugin"
printf '{"name":"rnd-framework","version":"9.9.9","description":"test"}\n' > "${vm_dir}/gitroot/plugins/rnd-framework/.claude-plugin/plugin.json"
( cd "${vm_dir}/gitroot" && git init -q && git commit --allow-empty -q -m "init" )

# Write a wrapper that runs session-start.sh with the fake PLUGIN_ROOT and git root
cat > "${vm_dir}/hooks/session-start-vm.sh" << VMSCRIPT
#!/usr/bin/env bash
source "${vm_dir}/hooks/lib.sh"
PLUGIN_ROOT="${vm_dir}"
GIT_ROOT_OVERRIDE="${vm_dir}/gitroot"
# Source the real session-start but override path-sensitive variables
$(tail -n +7 "${SESSION_START}" | sed "s|PLUGIN_ROOT=.*|PLUGIN_ROOT='${vm_dir}'|g")
VMSCRIPT

# Simpler: just run the original session-start.sh with PLUGIN_ROOT env var overridden.
# We rebuild SESSION_START in vm_dir, substituting PLUGIN_ROOT computation.
# Dynamically find the PLUGIN_ROOT line and replace it.
# This avoids hardcoded line numbers that break when comments/directives are added.
plugin_root_line="$(grep -n 'PLUGIN_ROOT=' "$SESSION_START" | head -1 | cut -d: -f1)"
{
  head -"$(( plugin_root_line - 1 ))" "$SESSION_START"
  printf 'PLUGIN_ROOT="%s"\n' "${vm_dir}"
  tail -n +"$(( plugin_root_line + 1 ))" "$SESSION_START"
} > "${vm_dir}/hooks/session-start.sh"
chmod +x "${vm_dir}/hooks/session-start.sh"

# Override git rev-parse inside the script with GIT_DIR pointing to our fake repo
vm_out="$(GIT_DIR="${vm_dir}/gitroot/.git" GIT_WORK_TREE="${vm_dir}/gitroot" \
  bash "${vm_dir}/hooks/session-start.sh" 2>/dev/null || true)"
vm_ctx="$(printf '%s' "$vm_out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"

if [[ "$vm_ctx" == *"mismatch"* ]] || [[ "$vm_ctx" == *"0.0.1"* && "$vm_ctx" == *"9.9.9"* ]]; then
  assert_eq "session-start includes version mismatch warning when versions differ" "pass" "pass"
else
  assert_eq "session-start includes version mismatch warning when versions differ" "pass" "fail"
fi

# ---------------------------------------------------------------------------
# pre-compact.sh tests
# ---------------------------------------------------------------------------
PRE_COMPACT="${HOOKS_DIR}/pre-compact.sh"

printf '%s\n' '--- pre-compact.sh ---'

# Quality: manifest regex is a named constant (not inline in the if/while condition)
# Look for a variable assignment that holds the regex pattern
if grep -qE 'readonly [A-Z_]+=.*T\[' "$PRE_COMPACT" 2>/dev/null || \
   grep -qE '^[A-Z_]+=.*T\[' "$PRE_COMPACT" 2>/dev/null || \
   grep -qE 'local -r [A-Z_]+=.*T\[' "$PRE_COMPACT" 2>/dev/null; then
  assert_eq "pre-compact manifest regex is a named constant" "pass" "pass"
else
  assert_eq "pre-compact manifest regex is a named constant" "pass" "fail"
fi

# Build wrapper: source shimmed lib (line 1-7 of pre-compact is shebang + comments + source)
make_wrapper "$PRE_COMPACT" 8 "${mock_dir}/run-pre-compact.sh"

precompact_exit=0
bash "${mock_dir}/run-pre-compact.sh" 2>/dev/null || precompact_exit=$?

state_file="${sessions_dir}/compact-state.json"
if [[ -f "$state_file" ]]; then
  assert_eq "pre-compact writes compact-state.json" "pass" "pass"

  plan_val="$(jq -r '.planSummary' "$state_file" 2>/dev/null || true)"
  iter_val="$(jq -r '.iterationCount' "$state_file" 2>/dev/null || true)"
  saved_val="$(jq -r '.savedAt' "$state_file" 2>/dev/null || true)"
  needle_val="$(jq -r '.verificationNeedle' "$state_file" 2>/dev/null || true)"

  [[ -n "$plan_val" && "$plan_val" != "null" ]] \
    && assert_eq "compact-state.json has planSummary" "pass" "pass" \
    || assert_eq "compact-state.json has planSummary" "pass" "fail"

  [[ -n "$iter_val" && "$iter_val" != "null" ]] \
    && assert_eq "compact-state.json has iterationCount" "pass" "pass" \
    || assert_eq "compact-state.json has iterationCount" "pass" "fail"

  [[ -n "$saved_val" && "$saved_val" != "null" ]] \
    && assert_eq "compact-state.json has savedAt" "pass" "pass" \
    || assert_eq "compact-state.json has savedAt" "pass" "fail"

  [[ -n "$needle_val" && "$needle_val" != "null" ]] \
    && assert_eq "compact-state.json has verificationNeedle" "pass" "pass" \
    || assert_eq "compact-state.json has verificationNeedle" "pass" "fail"
else
  assert_eq "pre-compact writes compact-state.json" "pass" "fail"
  assert_eq "compact-state.json has planSummary" "pass" "fail"
  assert_eq "compact-state.json has iterationCount" "pass" "fail"
  assert_eq "compact-state.json has savedAt" "pass" "fail"
  assert_eq "compact-state.json has verificationNeedle" "pass" "fail"
fi

# ---------------------------------------------------------------------------
# post-compact.sh tests
# ---------------------------------------------------------------------------
POST_COMPACT="${HOOKS_DIR}/post-compact.sh"

printf '%s\n' '--- post-compact.sh ---'

# Write compact-state.json into sessions_dir for post-compact to read
jq -cn \
  --arg planSummary "line1 line2 line3" \
  --arg currentTaskId "T5" \
  --argjson iterationCount 3 \
  --arg savedAt "2026-03-25T10:00:00Z" \
  --arg verificationNeedle "deadbeef" \
  '{planSummary:$planSummary,currentTaskId:$currentTaskId,iterationCount:$iterationCount,savedAt:$savedAt,verificationNeedle:$verificationNeedle}' \
  > "${sessions_dir}/compact-state.json"

# Build wrapper: post-compact shebang=line1, comment block lines 2-5, source line 6
make_wrapper "$POST_COMPACT" 7 "${mock_dir}/run-post-compact.sh"

pc_exit=0
pc_out="$(bash "${mock_dir}/run-post-compact.sh" 2>/dev/null)" || pc_exit=$?

assert_eq "post-compact exits 0" "0" "$pc_exit"

if printf '%s' "$pc_out" | jq . > /dev/null 2>&1; then
  assert_eq "post-compact outputs valid JSON" "pass" "pass"
else
  assert_eq "post-compact outputs valid JSON" "pass" "fail"
fi

pc_ctx="$(printf '%s' "$pc_out" | jq -r '.systemMessage // ""' 2>/dev/null || true)"
assert_contains "post-compact context contains task ID" "T5" "$pc_ctx"
assert_contains "post-compact context contains iteration count" "3" "$pc_ctx"
assert_contains "post-compact context contains verification needle" "deadbeef" "$pc_ctx"

# ---------------------------------------------------------------------------
# statusline.sh tests
# ---------------------------------------------------------------------------
STATUSLINE="${HOOKS_DIR}/statusline.sh"

printf '%s\n' '--- statusline.sh ---'

run_hook "$STATUSLINE" '{}'
assert_exit_code "statusline exits 0 with empty input" 0
sl_out="$HOOK_STDOUT"

if printf '%s' "$sl_out" | jq . > /dev/null 2>&1; then
  assert_eq "statusline outputs valid JSON" "pass" "pass"
else
  assert_eq "statusline outputs valid JSON" "pass" "fail"
fi

text_field="$(printf '%s' "$sl_out" | jq -r '.text // ""' 2>/dev/null || true)"
[[ -n "$text_field" ]] \
  && assert_eq "statusline has non-empty text field" "pass" "pass" \
  || assert_eq "statusline has non-empty text field" "pass" "fail"

# Test with rate limit data — should include percentages
sl_input_rates='{"rate_limits":{"fiveHour":{"used_percentage":42.7},"sevenDay":{"used_percentage":15.2}}}'
run_hook "$STATUSLINE" "$sl_input_rates"
sl_text_rates="$(printf '%s' "$HOOK_STDOUT" | jq -r '.text // ""' 2>/dev/null || true)"
assert_contains "statusline text includes 5h rate limit" "5h:" "$sl_text_rates"
assert_contains "statusline text includes 7d rate limit" "7d:" "$sl_text_rates"
assert_contains "statusline text includes 43% rounded rate" "43" "$sl_text_rates"

# Quality: phase names should not be set as bare inline string literals (use constants)
# The old pattern: phase="Integrating" etc. should be replaced with phase="$PHASE_*" references.
if grep -qE '^\s*phase="(Integrating|Verifying|Building|Planning|Idle)"' "$STATUSLINE" 2>/dev/null; then
  assert_eq "statusline phase names use constants not bare string literals" "no_bare_strings" "bare_strings"
else
  assert_eq "statusline phase names use constants not bare string literals" "no_bare_strings" "no_bare_strings"
fi

# ---------------------------------------------------------------------------
# setup.sh regression
# ---------------------------------------------------------------------------
printf '%s\n' '--- setup.sh regression ---'
SETUP_SH="${HOOKS_DIR}/setup.sh"

run_hook "$SETUP_SH"
assert_exit_code "setup exits 0 after rewrite" 0
setup_out="$HOOK_STDOUT"

if printf '%s' "$setup_out" | jq . > /dev/null 2>&1; then
  assert_eq "setup outputs valid JSON after rewrite" "pass" "pass"
else
  assert_eq "setup outputs valid JSON after rewrite" "pass" "fail"
fi

setup_event="$(printf '%s' "$setup_out" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null || true)"
assert_eq "setup hookEventName is Setup after rewrite" "Setup" "$setup_event"

setup_ctx="$(printf '%s' "$setup_out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
assert_contains "setup context contains Validation" "Validation:" "$setup_ctx"
assert_contains "setup context contains jq" "jq:" "$setup_ctx"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
report
