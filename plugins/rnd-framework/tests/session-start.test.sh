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
# Helper: run session-start with multiple env vars set
# ---------------------------------------------------------------------------
run_session_start_env() {
  local -a env_args=("$@")
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  env "${env_args[@]}" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# ---------------------------------------------------------------------------
# Helper: build an active-session fixture in a tmp config dir.
# Sets up:
#   ${tmp_config}/.rnd/.active-base-dir  → base_dir
#   ${base_dir}/.current-session         → session_id
#   ${base_dir}/sessions/${session_id}/  (directory)
# Prints the session dir path.
# ---------------------------------------------------------------------------
make_active_fixture() {
  local tmp_config="$1"
  local base_dir="${tmp_config}/.rnd/testslug/branches/main"
  local session_id="20260101-120000-abcd1234"
  local session_dir="${base_dir}/sessions/${session_id}"

  mkdir -p "$session_dir"
  printf '%s' "$session_id" > "${base_dir}/.current-session"

  mkdir -p "${tmp_config}/.rnd"
  printf '%s' "$base_dir" > "${tmp_config}/.rnd/.active-base-dir"

  printf '%s' "$session_dir"
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

# sessionTitle is set on startup/resume so the terminal title is phase-aware
# immediately, not only after the first prompt. Honored on Claude Code ≥ 2.1.152.
assert_contains "session-start JSON contains sessionTitle field" '"sessionTitle"' "$HOOK_STDOUT"

session_title_val="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.sessionTitle // ""' 2>/dev/null || true)"
if [[ "$session_title_val" == RND:* ]]; then
  assert_eq "session-start sessionTitle starts with 'RND:'" "ok" "ok"
else
  assert_eq "session-start sessionTitle starts with 'RND:'" "ok" "missing-or-malformed: $session_title_val"
fi

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
# Active session: full block with active RND_DIR
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: active session (full block) ---'

tmp_config_active="$(mktemp -d)"
session_dir_active="$(make_active_fixture "$tmp_config_active")"

run_session_start "CLAUDE_CONFIG_DIR=${tmp_config_active}"
assert_exit_code "active session: exits 0" 0

ctx_active="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"

# Full block must contain EXTREMELY_IMPORTANT
assert_contains "active session: additionalContext contains EXTREMELY_IMPORTANT" "<EXTREMELY_IMPORTANT>" "$ctx_active"

# Full block must contain skill body (rnd-framework content)
assert_contains "active session: additionalContext contains skill body" "rnd-framework" "$ctx_active"

# Full block must contain RND_DIR pointing to the active sessions/<id> path
assert_contains "active session: additionalContext contains RND_DIR label" "RND_DIR" "$ctx_active"
assert_contains "active session: RND_DIR ends in sessions/<id> path" "sessions/20260101-120000-abcd1234" "$ctx_active"

# sessionTitle should start with RND:
title_active="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.sessionTitle // ""' 2>/dev/null || true)"
if [[ "$title_active" == RND:* ]]; then
  assert_eq "active session: sessionTitle starts with RND:" "ok" "ok"
else
  assert_eq "active session: sessionTitle starts with RND:" "ok" "malformed: $title_active"
fi

rm -rf "$tmp_config_active"

# ---------------------------------------------------------------------------
# Inactive session: stub — no EXTREMELY_IMPORTANT, no RND_DIR, no skill body
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: inactive session (stub) ---'

tmp_config_inactive="$(mktemp -d)"
# No .current-session or .active-base-dir — no active pipeline

run_session_start "CLAUDE_CONFIG_DIR=${tmp_config_inactive}"
assert_exit_code "inactive session: exits 0" 0

ctx_inactive="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"

# Stub must NOT contain EXTREMELY_IMPORTANT
if [[ "$ctx_inactive" == *"<EXTREMELY_IMPORTANT>"* ]]; then
  assert_eq "inactive session: no EXTREMELY_IMPORTANT in stub" "absent" "present"
else
  assert_eq "inactive session: no EXTREMELY_IMPORTANT in stub" "absent" "absent"
fi

# Stub must NOT contain RND_DIR
if [[ "$ctx_inactive" == *"RND_DIR"* ]]; then
  assert_eq "inactive session: no RND_DIR in stub" "absent" "present"
else
  assert_eq "inactive session: no RND_DIR in stub" "absent" "absent"
fi

# Stub must mention rnd-framework, rnd-start, using-rnd-framework
assert_contains "inactive session: stub mentions rnd-framework" "rnd-framework" "$ctx_inactive"
assert_contains "inactive session: stub mentions /rnd-framework:rnd-start" "/rnd-framework:rnd-start" "$ctx_inactive"
assert_contains "inactive session: stub mentions using-rnd-framework" "using-rnd-framework" "$ctx_inactive"

# sessionTitle inactive → RND: <project>, no | segment
title_inactive="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.sessionTitle // ""' 2>/dev/null || true)"
if [[ "$title_inactive" == RND:* ]]; then
  assert_eq "inactive session: sessionTitle starts with RND:" "ok" "ok"
else
  assert_eq "inactive session: sessionTitle starts with RND:" "ok" "malformed: $title_inactive"
fi

if [[ "$title_inactive" == *"|"* ]]; then
  assert_eq "inactive session: sessionTitle has no | phase segment" "no-pipe" "has-pipe: $title_inactive"
else
  assert_eq "inactive session: sessionTitle has no | phase segment" "no-pipe" "no-pipe"
fi

rm -rf "$tmp_config_inactive"

# ---------------------------------------------------------------------------
# Stale pointer: .current-session points to missing session dir → stub
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: stale .current-session (dir-exists gate) ---'

tmp_config_stale="$(mktemp -d)"
stale_base="${tmp_config_stale}/.rnd/stale-slug/branches/main"
mkdir -p "$stale_base"
# Write .current-session pointing to a session dir that does NOT exist
printf 'ghost-session-id' > "${stale_base}/.current-session"
# Also write .active-base-dir so the fast path is taken (and the -d gate is exercised)
mkdir -p "${tmp_config_stale}/.rnd"
printf '%s' "$stale_base" > "${tmp_config_stale}/.rnd/.active-base-dir"

run_session_start "CLAUDE_CONFIG_DIR=${tmp_config_stale}"
assert_exit_code "stale pointer: exits 0" 0

ctx_stale="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"

# Stale pointer should fall through to stub — no full block
if [[ "$ctx_stale" == *"<EXTREMELY_IMPORTANT>"* ]]; then
  assert_eq "stale pointer: falls through to stub (no EXTREMELY_IMPORTANT)" "stub" "full-block"
else
  assert_eq "stale pointer: falls through to stub (no EXTREMELY_IMPORTANT)" "stub" "stub"
fi

if [[ "$ctx_stale" == *"RND_DIR"* ]]; then
  assert_eq "stale pointer: no RND_DIR in stub" "absent" "present"
else
  assert_eq "stale pointer: no RND_DIR in stub" "absent" "absent"
fi

rm -rf "$tmp_config_stale"

# ---------------------------------------------------------------------------
# No eager session: no sessions/<id> dir created after a clean-config run
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: no eager session created ---'

tmp_config_eager="$(mktemp -d)"

run_session_start "CLAUDE_CONFIG_DIR=${tmp_config_eager}"
assert_exit_code "no-eager-session: exits 0" 0

# Check that no sessions/ directory was created anywhere under the tmp config
sessions_found="$(find "$tmp_config_eager" -type d -name 'sessions' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$sessions_found" -eq 0 ]]; then
  assert_eq "no-eager-session: no sessions/ dir created" "0" "0"
else
  assert_eq "no-eager-session: no sessions/ dir created" "0" "$sessions_found"
fi

# Check the base dir exists (mkdir -p was called) and .session-git-root is written
base_dirs_found="$(find "$tmp_config_eager" -maxdepth 5 -name '.session-git-root' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$base_dirs_found" -ge 1 ]]; then
  assert_eq "no-eager-session: base dir created and .session-git-root written" "ok" "ok"
else
  assert_eq "no-eager-session: base dir created and .session-git-root written" "ok" "not-written"
fi

rm -rf "$tmp_config_eager"

# ---------------------------------------------------------------------------
# resolve_rnd_dir -c is gone from the hook
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: no resolve_rnd_dir -c call ---'

count_eager="$(grep -c 'resolve_rnd_dir -c' "${SCRIPT_DIR}/../hooks/session-start.sh" || true)"
assert_eq "no resolve_rnd_dir -c in session-start.sh" "0" "$count_eager"

# ---------------------------------------------------------------------------
# Single emit and exit 0: exactly one JSON object in both active and inactive
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: single JSON emit + exit 0 ---'

# Inactive branch
tmp_config_single_inactive="$(mktemp -d)"
run_session_start "CLAUDE_CONFIG_DIR=${tmp_config_single_inactive}"
assert_exit_code "single-emit inactive: exits 0" 0

count_inactive="$(printf '%s' "$HOOK_STDOUT" | jq -s 'length' 2>/dev/null || echo 0)"
assert_eq "single-emit inactive: exactly one JSON object" "1" "$count_inactive"

ctx_single_inactive="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // "null"' 2>/dev/null || true)"
if [[ "$ctx_single_inactive" != "null" && -n "$ctx_single_inactive" ]]; then
  assert_eq "single-emit inactive: additionalContext non-null" "ok" "ok"
else
  assert_eq "single-emit inactive: additionalContext non-null" "ok" "null-or-empty"
fi

title_single_inactive="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.sessionTitle // ""' 2>/dev/null || true)"
if [[ -n "$title_single_inactive" ]]; then
  assert_eq "single-emit inactive: sessionTitle non-empty" "ok" "ok"
else
  assert_eq "single-emit inactive: sessionTitle non-empty" "ok" "empty"
fi

rm -rf "$tmp_config_single_inactive"

# Active branch
tmp_config_single_active="$(mktemp -d)"
session_dir_single="$(make_active_fixture "$tmp_config_single_active")"

run_session_start "CLAUDE_CONFIG_DIR=${tmp_config_single_active}"
assert_exit_code "single-emit active: exits 0" 0

count_active="$(printf '%s' "$HOOK_STDOUT" | jq -s 'length' 2>/dev/null || echo 0)"
assert_eq "single-emit active: exactly one JSON object" "1" "$count_active"

ctx_single_active="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // "null"' 2>/dev/null || true)"
if [[ "$ctx_single_active" != "null" && -n "$ctx_single_active" ]]; then
  assert_eq "single-emit active: additionalContext non-null" "ok" "ok"
else
  assert_eq "single-emit active: additionalContext non-null" "ok" "null-or-empty"
fi

title_single_active="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.sessionTitle // ""' 2>/dev/null || true)"
if [[ -n "$title_single_active" ]]; then
  assert_eq "single-emit active: sessionTitle non-empty" "ok" "ok"
else
  assert_eq "single-emit active: sessionTitle non-empty" "ok" "empty"
fi

rm -rf "$tmp_config_single_active"

# ---------------------------------------------------------------------------
# Version warnings in both active and inactive branches (mock claude 2.1.89)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- session-start: version warnings in both branches ---'

mock_bin="$(mktemp -d)"
printf '#!/bin/sh\necho "2.1.89 (Claude Code)"\n' > "${mock_bin}/claude"
chmod +x "${mock_bin}/claude"

# Helper: run with both mock claude and CLAUDE_CONFIG_DIR
run_with_version_mock() {
  local cfg="$1"
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  PATH="${mock_bin}:${PATH}" env "CLAUDE_CONFIG_DIR=${cfg}" "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

# Inactive branch: mock claude 2.1.89
tmp_config_warn_inactive="$(mktemp -d)"
run_with_version_mock "$tmp_config_warn_inactive"
ctx_warn_inactive="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
assert_contains "version warning (inactive): additionalContext contains 'below the minimum'" "below the minimum" "$ctx_warn_inactive"
rm -rf "$tmp_config_warn_inactive"

# Active branch: mock claude 2.1.89
tmp_config_warn_active="$(mktemp -d)"
make_active_fixture "$tmp_config_warn_active" > /dev/null
run_with_version_mock "$tmp_config_warn_active"
ctx_warn_active="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
assert_contains "version warning (active): additionalContext contains 'below the minimum'" "below the minimum" "$ctx_warn_active"
rm -rf "$tmp_config_warn_active"

rm -rf "$mock_bin"

# ---------------------------------------------------------------------------
# Claude Code version check (preserved tests)
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

# Below minimum (previously at floor) → warning
run_with_mock_version "2.1.118"
ctx_old3="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
assert_contains "version 2.1.118 → warning in context" "below the minimum" "$ctx_old3"

# At minimum version → no warning
run_with_mock_version "2.1.139"
ctx_cur="$(printf '%s' "$HOOK_STDOUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || true)"
if [[ "$ctx_cur" == *"below the minimum"* ]]; then
  assert_eq "version 2.1.139 → no warning" "no warning" "warning present"
else
  assert_eq "version 2.1.139 → no warning" "no warning" "no warning"
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
