#!/usr/bin/env bash
# tests/lib.test.sh — Tests for hooks/lib.sh pure functions.
# Usage: bash tests/lib.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

LIB="${SCRIPT_DIR}/../hooks/lib.sh"
# shellcheck source=../hooks/lib.sh
source "$LIB"

printf '%s\n' '--- is_rnd_path ---'

# Matches .claude/.rnd/ pattern
if is_rnd_path "/Users/alice/.claude/.rnd/sessions/20260101/plan.md"; then
  assert_eq "is_rnd_path: .claude/.rnd/ path returns 0" "0" "0"
else
  assert_eq "is_rnd_path: .claude/.rnd/ path returns 0" "0" "1"
fi

# Matches .claude-personal/.rnd/ pattern
if is_rnd_path "/Users/alice/.claude-personal/.rnd/builds/T1.md"; then
  assert_eq "is_rnd_path: .claude-personal/.rnd/ path returns 0" "0" "0"
else
  assert_eq "is_rnd_path: .claude-personal/.rnd/ path returns 0" "0" "1"
fi

# Does NOT match plain .rnd/ without .claude prefix
if is_rnd_path "/Users/alice/.rnd/something"; then
  assert_eq "is_rnd_path: plain .rnd/ without .claude prefix returns 1" "1" "0"
else
  assert_eq "is_rnd_path: plain .rnd/ without .claude prefix returns 1" "1" "1"
fi

# Does NOT match .rnd.backup
if is_rnd_path "/Users/alice/.rnd.backup/foo"; then
  assert_eq "is_rnd_path: .rnd.backup does not match returns 1" "1" "0"
else
  assert_eq "is_rnd_path: .rnd.backup does not match returns 1" "1" "1"
fi

# Does NOT match regular path
if is_rnd_path "/Users/alice/Developer/project/src/main.ts"; then
  assert_eq "is_rnd_path: regular path returns 1" "1" "0"
else
  assert_eq "is_rnd_path: regular path returns 1" "1" "1"
fi

printf '\n%s\n' '--- is_plugin_artifact_path ---'

# Matches .claude/.rnd/ pattern
if is_plugin_artifact_path "/Users/alice/.claude/.rnd/sessions/20260101/plan.md"; then
  assert_eq "is_plugin_artifact_path: .claude/.rnd/ returns 0" "0" "0"
else
  assert_eq "is_plugin_artifact_path: .claude/.rnd/ returns 0" "0" "1"
fi

# Matches .claude-personal/.rnd/ pattern
if is_plugin_artifact_path "/Users/alice/.claude-personal/.rnd/design-51e58f69/sessions/20260322-181321-1b4a/plan.md"; then
  assert_eq "is_plugin_artifact_path: .claude-personal/.rnd/ returns 0" "0" "0"
else
  assert_eq "is_plugin_artifact_path: .claude-personal/.rnd/ returns 0" "0" "1"
fi

# Does NOT match plain .rnd/ without .claude prefix
if is_plugin_artifact_path "/Users/alice/.rnd/something"; then
  assert_eq "is_plugin_artifact_path: plain .rnd/ without .claude prefix returns 1" "1" "0"
else
  assert_eq "is_plugin_artifact_path: plain .rnd/ without .claude prefix returns 1" "1" "1"
fi

# Does NOT match regular path
if is_plugin_artifact_path "/Users/alice/Developer/project/src/main.ts"; then
  assert_eq "is_plugin_artifact_path: regular path returns 1" "1" "0"
else
  assert_eq "is_plugin_artifact_path: regular path returns 1" "1" "1"
fi

# Does NOT match plain .rnd/ without config dir prefix
if is_plugin_artifact_path "/Users/alice/.rnd/something"; then
  assert_eq "is_plugin_artifact_path: plain .rnd/ without config prefix returns 1" "1" "0"
else
  assert_eq "is_plugin_artifact_path: plain .rnd/ without config prefix returns 1" "1" "1"
fi

printf '\n%s\n' '--- is_plugin_cache_path ---'

# Matches .claude-personal/plugins/cache/
if is_plugin_cache_path "/Users/alice/.claude-personal/plugins/cache/oleksify/rnd-framework/0.12.5/SKILL.md"; then
  assert_eq "is_plugin_cache_path: .claude-personal/plugins/cache/ returns 0" "0" "0"
else
  assert_eq "is_plugin_cache_path: .claude-personal/plugins/cache/ returns 0" "0" "1"
fi

# Matches .claude/plugins/cache/
if is_plugin_cache_path "/Users/alice/.claude/plugins/cache/foo/bar/SKILL.md"; then
  assert_eq "is_plugin_cache_path: .claude/plugins/cache/ returns 0" "0" "0"
else
  assert_eq "is_plugin_cache_path: .claude/plugins/cache/ returns 0" "0" "1"
fi

# Does NOT match regular plugins/ path
if is_plugin_cache_path "/Users/alice/Developer/project/plugins/cache/foo.ts"; then
  assert_eq "is_plugin_cache_path: project plugins/cache/ without .claude returns 1" "1" "0"
else
  assert_eq "is_plugin_cache_path: project plugins/cache/ without .claude returns 1" "1" "1"
fi

printf '\n%s\n' '--- is_learnings_path ---'

# Matches .claude-personal/learnings/
if is_learnings_path "/Users/alice/.claude-personal/learnings/INDEX.md"; then
  assert_eq "is_learnings_path: .claude-personal/learnings/ returns 0" "0" "0"
else
  assert_eq "is_learnings_path: .claude-personal/learnings/ returns 0" "0" "1"
fi

# Matches .claude/learnings/
if is_learnings_path "/Users/alice/.claude/learnings/javascript.md"; then
  assert_eq "is_learnings_path: .claude/learnings/ returns 0" "0" "0"
else
  assert_eq "is_learnings_path: .claude/learnings/ returns 0" "0" "1"
fi

# Does NOT match project learnings/ without .claude prefix
if is_learnings_path "/Users/alice/Developer/project/learnings/notes.md"; then
  assert_eq "is_learnings_path: project learnings/ without .claude prefix returns 1" "1" "0"
else
  assert_eq "is_learnings_path: project learnings/ without .claude prefix returns 1" "1" "1"
fi

# Does NOT match regular path
if is_learnings_path "/Users/alice/Developer/project/src/main.ts"; then
  assert_eq "is_learnings_path: regular path returns 1" "1" "0"
else
  assert_eq "is_learnings_path: regular path returns 1" "1" "1"
fi

printf '\n%s\n' '--- allow_json ---'

output="$(allow_json)"
assert_contains "allow_json: contains permissionDecision" '"permissionDecision"' "$output"
assert_contains "allow_json: contains allow value" '"allow"' "$output"
assert_contains "allow_json: contains hookEventName" '"hookEventName"' "$output"
assert_contains "allow_json: contains PreToolUse" '"PreToolUse"' "$output"

# Verify it's valid JSON
if printf '%s' "$output" | jq . > /dev/null 2>&1; then
  assert_eq "allow_json: is valid JSON" "0" "0"
else
  assert_eq "allow_json: is valid JSON" "0" "1"
fi

printf '\n%s\n' '--- advisory_json ---'

adv_out="$(advisory_json "Test advisory message")"
assert_contains "advisory_json: contains additionalContext key" '"additionalContext"' "$adv_out"
assert_contains "advisory_json: contains the message" "Test advisory message" "$adv_out"

# Verify it's valid JSON
if printf '%s' "$adv_out" | jq . > /dev/null 2>&1; then
  assert_eq "advisory_json: is valid JSON" "0" "0"
else
  assert_eq "advisory_json: is valid JSON" "0" "1"
fi

# Advisory with special characters is properly escaped
adv_special="$(advisory_json 'Message with "quotes" and newlines')"
if printf '%s' "$adv_special" | jq . > /dev/null 2>&1; then
  assert_eq "advisory_json: special characters produce valid JSON" "0" "0"
else
  assert_eq "advisory_json: special characters produce valid JSON" "0" "1"
fi

printf '\n%s\n' '--- SESSION_ID_RE constant ---'

assert_eq "SESSION_ID_RE is defined" "0" "$([ -n "${SESSION_ID_RE:-}" ] && echo 0 || echo 1)"
assert_eq "SESSION_ID_RE value matches expected pattern" '^[0-9]{8}-[0-9]{6}-[0-9a-f]{4,8}$' "${SESSION_ID_RE:-}"

# Verify the constant is readonly
if ( SESSION_ID_RE="mutated" ) 2>/dev/null; then
  assert_eq "SESSION_ID_RE is readonly" "readonly" "mutable"
else
  assert_eq "SESSION_ID_RE is readonly" "readonly" "readonly"
fi

printf '\n%s\n' '--- active_session_dir: session ID validation ---'

# Set up a temporary directory tree mimicking the config/rnd layout
_SESSION_TMPDIR="$(mktemp -d)"
_session_cleanup() { rm -rf "$_SESSION_TMPDIR"; }
trap _session_cleanup EXIT

_BASE="${_SESSION_TMPDIR}/myproject-ab123456"
mkdir -p "${_BASE}/sessions"
mkdir -p "${_SESSION_TMPDIR}/.rnd"
printf '%s' "$_BASE" > "${_SESSION_TMPDIR}/.rnd/.active-base-dir"

# Use the temp dir as config dir
CLAUDE_CONFIG_DIR="$_SESSION_TMPDIR"
unset CLAUDE_PLUGIN_ROOT 2>/dev/null || true

# Helper: reset process-level cache between tests
_reset_session_cache() {
  _ACTIVE_SESSION_RESOLVED=0
  _ACTIVE_SESSION_CACHE=""
}

# Invalid: path traversal in session ID
printf '%s' '../../../etc/passwd' > "${_BASE}/.current-session"
_reset_session_cache
_rc=0; active_session_dir > /dev/null 2>&1 || _rc=$?
assert_eq "active_session_dir: path traversal session ID returns 1" "1" "$_rc"

# Invalid: session ID with spaces
printf '%s' '20260101-120000-ab cd' > "${_BASE}/.current-session"
_reset_session_cache
_rc=0; active_session_dir > /dev/null 2>&1 || _rc=$?
assert_eq "active_session_dir: session ID with spaces returns 1" "1" "$_rc"

# Invalid: uppercase hex
printf '%s' '20260101-120000-ABCD' > "${_BASE}/.current-session"
_reset_session_cache
_rc=0; active_session_dir > /dev/null 2>&1 || _rc=$?
assert_eq "active_session_dir: uppercase hex session ID returns 1" "1" "$_rc"

# Invalid: empty session ID
printf '' > "${_BASE}/.current-session"
_reset_session_cache
_rc=0; active_session_dir > /dev/null 2>&1 || _rc=$?
assert_eq "active_session_dir: empty session ID returns 1" "1" "$_rc"

# Invalid: wrong separator
printf '%s' '2026/0101-120000-abcd' > "${_BASE}/.current-session"
_reset_session_cache
_rc=0; active_session_dir > /dev/null 2>&1 || _rc=$?
assert_eq "active_session_dir: wrong separator in session ID returns 1" "1" "$_rc"

# Valid: standard session ID
_VALID_ID="20260327-101827-50f7"
mkdir -p "${_BASE}/sessions/${_VALID_ID}"
printf '%s' "$_VALID_ID" > "${_BASE}/.current-session"
_reset_session_cache
_got_dir=""
_got_dir="$(active_session_dir 2>/dev/null)" || true
assert_eq "active_session_dir: valid session ID returns correct path" "${_BASE}/sessions/${_VALID_ID}" "$_got_dir"

# Valid: all-zero hex part
_VALID_ID2="20260101-000000-0000"
mkdir -p "${_BASE}/sessions/${_VALID_ID2}"
printf '%s' "$_VALID_ID2" > "${_BASE}/.current-session"
_reset_session_cache
_got_dir2=""
_got_dir2="$(active_session_dir 2>/dev/null)" || true
assert_eq "active_session_dir: valid ID with all-zero hex returns correct path" "${_BASE}/sessions/${_VALID_ID2}" "$_got_dir2"

# Valid: all-f hex part
_VALID_ID3="20991231-235959-ffff"
mkdir -p "${_BASE}/sessions/${_VALID_ID3}"
printf '%s' "$_VALID_ID3" > "${_BASE}/.current-session"
_reset_session_cache
_got_dir3=""
_got_dir3="$(active_session_dir 2>/dev/null)" || true
assert_eq "active_session_dir: valid ID with all-f hex returns correct path" "${_BASE}/sessions/${_VALID_ID3}" "$_got_dir3"

report
