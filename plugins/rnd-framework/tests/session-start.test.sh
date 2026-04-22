#!/usr/bin/env bash
# tests/session-start.test.sh — Tests for hooks/session-start.sh
# Usage: bash tests/session-start.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/session-start.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Helper: run session-start with optional CLAUDE_CONFIG_DIR override
# ---------------------------------------------------------------------------
run_session_start() {
  local env_override="${1:-}"
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  if [[ -n "$env_override" ]]; then
    env "$env_override" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  else
    "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  fi
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# ---------------------------------------------------------------------------
# outputs SessionStart JSON
# ---------------------------------------------------------------------------
printf '%s\n' '--- session-start: basic output ---'

run_session_start
assert_exit_code "session-start exits 0" 0

# Must be valid JSON
if printf '%s' "$HOOK_STDOUT" | jq . > /dev/null 2>&1; then
  assert_eq "session-start outputs valid JSON" "0" "0"
else
  assert_eq "session-start outputs valid JSON" "0" "1"
fi

# Must contain hookEventName: SessionStart
assert_contains "session-start JSON contains SessionStart hookEventName" '"SessionStart"' "$HOOK_STDOUT"

# Must contain hookSpecificOutput
assert_contains "session-start JSON contains hookSpecificOutput" '"hookSpecificOutput"' "$HOOK_STDOUT"

# Must contain additionalContext
assert_contains "session-start JSON contains additionalContext" '"additionalContext"' "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# strips frontmatter — skill content should not contain raw --- delimiters
# from the frontmatter block
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: strips frontmatter ---'

# Extract additionalContext value
ctx="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"

# The skill content should contain actual text (from using-rnd-framework SKILL.md)
assert_contains "session-start additionalContext is non-empty" "rnd-framework" "$ctx"

# The YAML frontmatter block should be stripped — the first --- should not
# appear at the start of the injected skill content
# (frontmatter lines like "name: ..." or "description: ..." should be absent)
if printf '%s' "$ctx" | grep -q '^name:'; then
  assert_eq "session-start frontmatter name: field not in context" "not present" "present"
else
  assert_eq "session-start frontmatter name: field not in context" "not present" "not present"
fi

# ---------------------------------------------------------------------------
# includes RND_DIR when a session is active
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: RND_DIR in output ---'

# Create a temporary config dir with an active session to exercise the RND_DIR path
tmp_config="$(mktemp -d)"
tmp_base="${tmp_config}/.rnd/claude-testslug"
mkdir -p "${tmp_base}/sessions/20260101-120000-test"
printf '20260101-120000-test' > "${tmp_base}/.current-session"

run_session_start "CLAUDE_CONFIG_DIR=${tmp_config}"
assert_exit_code "session-start with active session exits 0" 0

ctx_with_rnd="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
assert_contains "session-start context includes RND_DIR label" "RND_DIR" "$ctx_with_rnd"

rm -rf "$tmp_config"

# ---------------------------------------------------------------------------
# Claude Code version check
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: Claude Code version check ---'

# Create a mock claude binary that returns a specific version
mock_bin="$(mktemp -d)"

# Helper: run session-start with a mock claude version
run_with_mock_version() {
  local version="$1"
  printf '#!/bin/sh\necho "%s (Claude Code)"\n' "$version" > "${mock_bin}/claude"
  chmod +x "${mock_bin}/claude"
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  PATH="${mock_bin}:${PATH}" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# Below minimum version → warning
run_with_mock_version "2.1.89"
ctx_old="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
assert_contains "version 2.1.89 → warning in context" "below the minimum" "$ctx_old"

# Below new minimum (previously at floor) → warning
run_with_mock_version "2.1.97"
ctx_old2="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
assert_contains "version 2.1.97 → warning in context" "below the minimum" "$ctx_old2"

# At minimum version → no warning
run_with_mock_version "2.1.117"
ctx_cur="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
if [[ "$ctx_cur" == *"below the minimum"* ]]; then
  assert_eq "version 2.1.117 → no warning" "no warning" "warning present"
else
  assert_eq "version 2.1.117 → no warning" "no warning" "no warning"
fi

# Above minimum version → no warning
run_with_mock_version "2.2.0"
ctx_new="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
if [[ "$ctx_new" == *"below the minimum"* ]]; then
  assert_eq "version 2.2.0 → no warning" "no warning" "warning present"
else
  assert_eq "version 2.2.0 → no warning" "no warning" "no warning"
fi

# claude returning error → no warning (graceful degradation)
printf '#!/bin/sh\nexit 1\n' > "${mock_bin}/claude"
chmod +x "${mock_bin}/claude"
run_with_mock_version "error"
# Re-create the error-exit mock (run_with_mock_version overwrites it)
printf '#!/bin/sh\nexit 1\n' > "${mock_bin}/claude"
chmod +x "${mock_bin}/claude"
HOOK_EXIT=0
tmp_out="$(mktemp)"; tmp_err="$(mktemp)"
PATH="${mock_bin}:${PATH}" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
HOOK_STDOUT="$(cat "$tmp_out")"; HOOK_STDERR="$(cat "$tmp_err")"
rm -f "$tmp_out" "$tmp_err"
assert_exit_code "claude error → exits 0" 0
ctx_missing="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
if [[ "$ctx_missing" == *"below the minimum"* ]]; then
  assert_eq "claude error → no version warning" "no warning" "warning present"
else
  assert_eq "claude error → no version warning" "no warning" "no warning"
fi

rm -rf "$mock_bin"

report
