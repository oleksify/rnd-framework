#!/usr/bin/env bash
# tests/glob-grep-gate.test.sh — Tests for hooks/glob-grep-gate.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/glob-grep-gate.sh"

PASS=0
FAIL=0

run_hook() {
  local stdin_json="$1"
  HOOK_STDOUT=""
  HOOK_STDERR=""
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$stdin_json" | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(< "$tmp_out")"
  HOOK_STDERR="$(< "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

pass() { printf '  PASS  %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  FAIL  %s — %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

assert_exit() {
  local name="$1" expected="$2"
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then pass "$name"; else fail "$name" "expected exit $expected, got $HOOK_EXIT"; fi
}

assert_stdout_contains() {
  local name="$1" needle="$2"
  if [[ "$HOOK_STDOUT" == *"$needle"* ]]; then pass "$name"; else fail "$name" "expected stdout to contain '$needle', got: '$HOOK_STDOUT'"; fi
}

assert_stdout_empty() {
  local name="$1"
  if [[ -z "$HOOK_STDOUT" ]]; then pass "$name"; else fail "$name" "expected empty stdout, got: '$HOOK_STDOUT'"; fi
}

assert_stderr_contains() {
  local name="$1" needle="$2"
  if [[ "$HOOK_STDERR" == *"$needle"* ]]; then pass "$name"; else fail "$name" "expected stderr to contain '$needle', got: '$HOOK_STDERR'"; fi
}

# ---------------------------------------------------------------------------
# Information barrier — self-assessment
# ---------------------------------------------------------------------------

# Grep + self-assessment + rnd-verifier → block
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/.claude/.rnd/builds/T3-self-assessment.md","pattern":"HIGH"},"agent_type":"rnd-verifier"}'
assert_exit "Grep self-assessment + verifier → exit 2" 2
assert_stderr_contains "Grep self-assessment + verifier → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# Grep + self-assessment + empty agent_type → allow (orchestrator is the legitimate consumer)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/.rnd/builds/T3-self-assessment.md","pattern":"HIGH"},"agent_type":""}'
assert_exit "Grep self-assessment + empty agent_type → exit 0 (orchestrator allowed)" 0

# Grep + self-assessment + null/missing agent_type key → allow (treated as orchestrator)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/.rnd/builds/T3-self-assessment.md","pattern":"HIGH"}}'
assert_exit "Grep self-assessment + null agent_type → exit 0 (orchestrator allowed)" 0

# Glob + self-assessment + empty agent_type → allow (orchestrator)
run_hook '{"tool_name":"Glob","tool_input":{"path":"/Users/alice/.rnd/builds","pattern":"*self-assessment*"},"agent_type":""}'
assert_exit "Glob self-assessment (in pattern) + empty agent_type → exit 0 (orchestrator allowed)" 0

# Glob + self-assessment in path + empty agent_type → allow (orchestrator)
run_hook '{"tool_name":"Glob","tool_input":{"path":"/Users/alice/.rnd/builds/T3-self-assessment.md","pattern":"*.md"},"agent_type":""}'
assert_exit "Glob self-assessment (in path) + empty agent_type → exit 0 (orchestrator allowed)" 0

# Grep + self-assessment + rnd-builder → allowed (exit 0, empty stdout)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/.rnd/builds/T3-self-assessment.md","pattern":"HIGH"},"agent_type":"rnd-builder"}'
assert_exit "Grep self-assessment + rnd-builder → exit 0" 0
assert_stdout_empty "Grep self-assessment + rnd-builder → empty stdout"

# Case-insensitive: SELF-ASSESSMENT uppercase + empty agent_type → allow (orchestrator)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/.rnd/builds/T3-SELF-ASSESSMENT.md","pattern":"HIGH"},"agent_type":""}'
assert_exit "Grep SELF-ASSESSMENT uppercase + empty agent_type → exit 0 (orchestrator allowed)" 0

# .rnd/ path WITHOUT self-assessment → auto-allow (barrier does not interfere)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/.claude/.rnd/builds/T3-manifest.md","pattern":"PASS"},"agent_type":""}'
assert_exit ".rnd/ path without self-assessment → exit 0" 0
assert_stdout_contains ".rnd/ path without self-assessment → allow JSON" '"permissionDecision":"allow"'

# .rnd/ path WITH self-assessment + empty agent_type → allow (orchestrator)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/.claude/.rnd/builds/T3-self-assessment.md","pattern":"HIGH"},"agent_type":""}'
assert_exit ".rnd/ + self-assessment + empty agent_type → exit 0 (orchestrator allowed)" 0

# regular non-.rnd/ path → no opinion (exit 0, empty stdout)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/project/src","pattern":"foo"},"agent_type":""}'
assert_exit "regular path with agent_type → exit 0" 0
assert_stdout_empty "regular path with agent_type → empty stdout"

# ---------------------------------------------------------------------------
# .rnd/ path → auto-allow
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Glob","tool_input":{"path":"/Users/alice/.claude-personal/.rnd/slug/sessions/123/verifications","pattern":"*.test.ts"}}'
assert_exit "Glob .rnd/ path → exit 0" 0
assert_stdout_contains "Glob .rnd/ path → allow JSON" '"permissionDecision":"allow"'

# Grep: .rnd/ path → auto-allow

run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/alice/.claude/.rnd/slug/sessions/123/builds","pattern":"PASS"}}'
assert_exit "Grep .rnd/ path → exit 0" 0
assert_stdout_contains "Grep .rnd/ path → allow JSON" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# regular path → no opinion
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Glob","tool_input":{"path":"/Users/alice/project/src","pattern":"*.ts"}}'
assert_exit "regular path → exit 0" 0
assert_stdout_empty "regular path → empty stdout (no opinion)"

# no path → no opinion

run_hook '{"tool_name":"Glob","tool_input":{"pattern":"*.ts"}}'
assert_exit "no path → exit 0" 0
assert_stdout_empty "no path → empty stdout (no opinion)"

# .rnd without .claude prefix → no opinion

run_hook '{"tool_name":"Glob","tool_input":{"path":"/tmp/.rnd/sessions/123","pattern":"*.md"}}'
assert_exit ".rnd without .claude → exit 0" 0
assert_stdout_empty ".rnd without .claude → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

run_hook "not json"
assert_exit "malformed → exit 0" 0
assert_stdout_empty "malformed → empty stdout"

run_hook ""
assert_exit "empty → exit 0" 0
assert_stdout_empty "empty → empty stdout"

# plugin cache path → no opinion (only artifact paths auto-allowed)

run_hook '{"tool_name":"Glob","tool_input":{"path":"/Users/alice/.claude/plugins/cache/rnd-framework/skills","pattern":"*.md"}}'
assert_exit "plugin cache path → exit 0" 0
assert_stdout_empty "plugin cache path → empty stdout (no opinion)"

# ---------------------------------------------------------------------------
# Cleanup barrier tests
# ---------------------------------------------------------------------------

# /cleanup/ path with verifier → block
run_hook '{"tool_name":"Grep","tool_input":{"path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/cleanup/T3-cleanup-report.md","pattern":"dead"},"agent_type":"rnd-verifier"}'
assert_exit   "/cleanup/ + verifier → exit 2" 2
assert_stderr_contains "/cleanup/ + verifier → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

# /cleanup/ path with empty agent_type → allow (orchestrator is the legitimate consumer)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/cleanup/T3-cleanup-report.md","pattern":"dead"},"agent_type":""}'
assert_exit   "/cleanup/ + empty agent_type → exit 0 (orchestrator allowed)" 0

# /cleanup/ path with rnd-builder → exit 0, empty stdout (not auto-allowed)
run_hook '{"tool_name":"Grep","tool_input":{"path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/cleanup/T3-cleanup-report.md","pattern":"dead"},"agent_type":"rnd-builder"}'
assert_exit   "/cleanup/ + rnd-builder → exit 0" 0
assert_stdout_empty "/cleanup/ + rnd-builder → empty stdout (not auto-allowed)"

# /cleanup/ in pattern with verifier → block
run_hook '{"tool_name":"Glob","tool_input":{"path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd","pattern":"/cleanup/*.md"},"agent_type":"rnd-verifier"}'
assert_exit   "/cleanup/ in Glob pattern + verifier → exit 2" 2

# Word "cleanup" without /cleanup/ segment → not affected
run_hook '{"tool_name":"Grep","tool_input":{"path":"/Users/someone/project/src/cleanup.ts","pattern":"dead"},"agent_type":"rnd-verifier"}'
assert_exit   "cleanup.ts (no /cleanup/ segment) + verifier → exit 0" 0

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
