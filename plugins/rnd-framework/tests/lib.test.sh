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

# Matches .factory/.rnd/ pattern
if is_plugin_artifact_path "/Users/alice/.factory/.rnd/sessions/123/plan.md"; then
  assert_eq "is_plugin_artifact_path: .factory/.rnd/ returns 0" "0" "0"
else
  assert_eq "is_plugin_artifact_path: .factory/.rnd/ returns 0" "0" "1"
fi

# Matches .factory/.rnd/ pattern
if is_plugin_artifact_path "/Users/alice/.factory/.rnd/slug/sessions/123/plan.md"; then
  assert_eq "is_plugin_artifact_path: .factory/.rnd/ returns 0" "0" "0"
else
  assert_eq "is_plugin_artifact_path: .factory/.rnd/ returns 0" "0" "1"
fi

# Does NOT match .factory/ path without .rnd/ or .rnd/
if is_plugin_artifact_path "/Users/alice/.factory/something-else/file.md"; then
  assert_eq "is_plugin_artifact_path: .factory/something-else does not match returns 1" "1" "0"
else
  assert_eq "is_plugin_artifact_path: .factory/something-else does not match returns 1" "1" "1"
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

# Matches .factory/plugins/cache/
if is_plugin_cache_path "/Users/alice/.factory/plugins/cache/rnd/SKILL.md"; then
  assert_eq "is_plugin_cache_path: .factory/plugins/cache/ returns 0" "0" "0"
else
  assert_eq "is_plugin_cache_path: .factory/plugins/cache/ returns 0" "0" "1"
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

# Matches .factory/learnings/
if is_learnings_path "/Users/alice/.factory/learnings/javascript.md"; then
  assert_eq "is_learnings_path: .factory/learnings/ returns 0" "0" "0"
else
  assert_eq "is_learnings_path: .factory/learnings/ returns 0" "0" "1"
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

report
