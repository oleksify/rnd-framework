#!/usr/bin/env bash
# Tests for hooks/evidence-pack-gate.sh
# Usage: bash tests/evidence-pack-gate.test.sh
# Exits 0 if all tests pass, 1 if any fail.

set -euo pipefail

export CLAUDE_CONFIG_DIR="$(mktemp -d)"
export HOME="$(mktemp -d)"
unset RND_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/../hooks/evidence-pack-gate.sh"

PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_hook() {
  local stdin_json="$1"
  HOOK_STDOUT=""
  HOOK_STDERR=""
  HOOK_EXIT=0
  local tmp_out tmp_err
  tmp_out="$(mktemp)"
  tmp_err="$(mktemp)"
  printf '%s' "$stdin_json" | "$HOOK" >"$tmp_out" 2>"$tmp_err" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$tmp_out")"
  HOOK_STDERR="$(cat "$tmp_err")"
  rm -f "$tmp_out" "$tmp_err"
}

pass() {
  local name="$1"
  printf 'PASS  %s\n' "$name"
  PASS=$((PASS + 1))
}

fail() {
  local name="$1"
  local detail="$2"
  printf 'FAIL  %s — %s\n' "$name" "$detail"
  FAIL=$((FAIL + 1))
}

assert_exit() {
  local name="$1"
  local expected="$2"
  if [[ "$HOOK_EXIT" -eq "$expected" ]]; then
    pass "$name"
  else
    fail "$name" "expected exit $expected, got $HOOK_EXIT"
  fi
}

assert_stdout_contains() {
  local name="$1"
  local needle="$2"
  if [[ "$HOOK_STDOUT" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected stdout to contain '$needle', got: '$HOOK_STDOUT'"
  fi
}

assert_stdout_empty() {
  local name="$1"
  if [[ -z "$HOOK_STDOUT" ]]; then
    pass "$name"
  else
    fail "$name" "expected empty stdout, got: '$HOOK_STDOUT'"
  fi
}

assert_stderr_contains() {
  local name="$1"
  local needle="$2"
  if [[ "$HOOK_STDERR" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name" "expected stderr to contain '$needle', got: '$HOOK_STDERR'"
  fi
}

# ---------------------------------------------------------------------------
# Fixture helpers — write temp manifest files under the configured .rnd/ dir
# ---------------------------------------------------------------------------

RND_BASE="$(mktemp -d)"
FAKE_CONFIG="${CLAUDE_CONFIG_DIR}"
FAKE_RND="${FAKE_CONFIG}/.rnd"

write_manifest() {
  local task_id="$1"
  local content="$2"
  local dir="${FAKE_RND}/evidence/${task_id}"
  mkdir -p "$dir"
  printf '%s' "$content" >"${dir}/manifest.json"
  printf '%s' "${dir}/manifest.json"
}

cleanup() {
  rm -rf "$RND_BASE"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

VALID_MANIFEST_CONTENT='{
  "tool": "pytest",
  "command_argv": ["python", "-m", "pytest", "tests/"],
  "cwd": "/project",
  "started_at": "2026-05-10T09:00:00Z",
  "finished_at": "2026-05-10T09:01:00Z",
  "exit_code": 0,
  "stdout_path": "/rnd/evidence/T1/stdout.txt",
  "stderr_path": "/rnd/evidence/T1/stderr.txt",
  "inputs": [{"path": "tests/test_foo.py", "sha256": "abc123"}]
}'

make_disallowed_manifest() {
  local field="$1"
  printf '%s' "$VALID_MANIFEST_CONTENT" | jq --arg f "$field" '. + {($f): "some text"}'
}

VALID_PATH="$(write_manifest "T1" "$VALID_MANIFEST_CONTENT")"

NOTES_PATH="$(write_manifest "T2" "$(make_disallowed_manifest notes)")"
SUMMARY_PATH="$(write_manifest "T3" "$(make_disallowed_manifest summary)")"
CONFIDENCE_PATH="$(write_manifest "T4" "$(make_disallowed_manifest confidence)")"
REASONING_PATH="$(write_manifest "T5" "$(make_disallowed_manifest reasoning)")"
EXPLANATION_PATH="$(write_manifest "T6" "$(make_disallowed_manifest explanation)")"

# ---------------------------------------------------------------------------
# Tests: disallowed fields → EVIDENCE PACK BARRIER
# ---------------------------------------------------------------------------

for disallowed_field_test in notes summary confidence reasoning explanation; do
  case "$disallowed_field_test" in
    notes)       test_path="$NOTES_PATH" ;;
    summary)     test_path="$SUMMARY_PATH" ;;
    confidence)  test_path="$CONFIDENCE_PATH" ;;
    reasoning)   test_path="$REASONING_PATH" ;;
    explanation) test_path="$EXPLANATION_PATH" ;;
  esac

  run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${test_path}\"},\"agent_type\":\"rnd-verifier\"}"
  assert_exit "verifier reads manifest with '${disallowed_field_test}' → exit 2" 2
  assert_stderr_contains "verifier reads manifest with '${disallowed_field_test}' → EVIDENCE PACK BARRIER on stderr" "EVIDENCE PACK BARRIER"
done

# ---------------------------------------------------------------------------
# Tests: schema-valid manifest → allow JSON
# ---------------------------------------------------------------------------

run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${VALID_PATH}\"},\"agent_type\":\"rnd-verifier\"}"
assert_exit "verifier reads valid manifest → exit 0" 0
assert_stdout_contains "verifier reads valid manifest → allow JSON in stdout" '"permissionDecision":"allow"'

# ---------------------------------------------------------------------------
# Tests: information barrier preserved for self-assessment and /briefs/
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/builds/T1-self-assessment.md"},"agent_type":"rnd-verifier"}'
assert_exit "verifier reads self-assessment → exit 2" 2
assert_stderr_contains "verifier reads self-assessment → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/sessions/20260101-120000-abcd/briefs/T1-briefs.md"},"agent_type":"rnd-verifier"}'
assert_exit "verifier reads /briefs/ path → exit 2" 2
assert_stderr_contains "verifier reads /briefs/ path → INFORMATION BARRIER on stderr" "INFORMATION BARRIER"

run_hook '{"tool_name":"Read","tool_input":{"file_path":"/home/user/.claude/.rnd/builds/T1-self-assessment.md"},"agent_type":""}'
assert_exit "empty agent_type reads self-assessment → exit 0 (orchestrator allowed)" 0

# ---------------------------------------------------------------------------
# Tests: non-manifest .rnd/ paths by verifier → no opinion
# ---------------------------------------------------------------------------

run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${FAKE_RND}/builds/T1-manifest.md\"},\"agent_type\":\"rnd-verifier\"}"
assert_exit "verifier reads non-manifest .rnd/ path → exit 0" 0
assert_stdout_empty "verifier reads non-manifest .rnd/ path → empty stdout"

# evidence/ dir but wrong filename (not manifest.json)
run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${FAKE_RND}/evidence/T1/stdout.txt\"},\"agent_type\":\"rnd-verifier\"}"
assert_exit "verifier reads evidence stdout.txt (not manifest.json) → exit 0" 0
assert_stdout_empty "verifier reads evidence stdout.txt → empty stdout"

# ---------------------------------------------------------------------------
# Tests: non-.rnd/ paths → no opinion
# ---------------------------------------------------------------------------

run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/Developer/myproject/src/main.ts"},"agent_type":"rnd-verifier"}'
assert_exit "verifier reads non-.rnd/ path → exit 0" 0
assert_stdout_empty "verifier reads non-.rnd/ path → empty stdout"

run_hook '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/Developer/myproject/src/main.ts"},"agent_type":""}'
assert_exit "empty agent_type reads non-.rnd/ path → exit 0" 0
assert_stdout_empty "empty agent_type reads non-.rnd/ path → empty stdout"

# ---------------------------------------------------------------------------
# Tests: non-verifier reading a manifest → no opinion (not blocked)
# ---------------------------------------------------------------------------

run_hook "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"${NOTES_PATH}\"},\"agent_type\":\"rnd-builder\"}"
assert_exit "builder reads invalid manifest → exit 0 (gate only applies to verifier)" 0
assert_stdout_empty "builder reads invalid manifest → empty stdout"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
