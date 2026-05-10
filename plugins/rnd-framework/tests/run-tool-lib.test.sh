#!/usr/bin/env bash
# tests/run-tool-lib.test.sh — Tests for lib/run-tool.sh and lib/tools.json.
# Usage: bash tests/run-tool-lib.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUN_TOOL="${PLUGIN_DIR}/lib/run-tool.sh"
TOOLS_JSON="${PLUGIN_DIR}/lib/tools.json"

# Use RND_DIR for temp files per project convention
WORK_DIR="${RND_DIR:-/tmp/run-tool-test-$$}/run-tool-test-$$"
mkdir -p "$WORK_DIR"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# tools.json validation
# ---------------------------------------------------------------------------
printf '%s\n' '--- tools.json validity ---'

TOOLS_VALID="$(jq 'type == "object"' "$TOOLS_JSON")"
assert_eq "tools.json is a valid JSON object" "true" "$TOOLS_VALID"

for tool in pytest jest vitest tsc eslint mypy dialyzer bun cargo mix ruff biome; do
  HAS_FLAGS="$(jq --arg t "$tool" '.[$t].structured_flags | type == "array"' "$TOOLS_JSON")"
  assert_eq "tools.json[$tool].structured_flags is array" "true" "$HAS_FLAGS"

  HAS_EXT="$(jq --arg t "$tool" '.[$t].structured_ext | type == "string"' "$TOOLS_JSON")"
  assert_eq "tools.json[$tool].structured_ext is string" "true" "$HAS_EXT"
done

# ---------------------------------------------------------------------------
# Passthrough mode (RND_EVIDENCE_PACK unset)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- passthrough mode ---'

HOOK_EXIT=0
unset RND_EVIDENCE_PACK || true
actual_out="$(bash "$RUN_TOOL" -- printf '%s' "hello" 2>/dev/null)" || HOOK_EXIT=$?
assert_eq "passthrough: exit code 0" "0" "$HOOK_EXIT"
assert_eq "passthrough: stdout is command output" "hello" "$actual_out"

HOOK_EXIT=0
RND_EVIDENCE_PACK=0 actual_out2="$(bash "$RUN_TOOL" -- printf '%s' "world" 2>/dev/null)" || HOOK_EXIT=$?
assert_eq "passthrough RND_EVIDENCE_PACK=0: exit code 0" "0" "$HOOK_EXIT"
assert_eq "passthrough RND_EVIDENCE_PACK=0: stdout is command output" "world" "$actual_out2"

# Propagates non-zero exit from wrapped command
HOOK_EXIT=0
bash "$RUN_TOOL" -- bash -c 'exit 42' 2>/dev/null || HOOK_EXIT=$?
assert_eq "passthrough: propagates non-zero exit code" "42" "$HOOK_EXIT"

# ---------------------------------------------------------------------------
# Pack mode: manifest.json written with all required fields
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pack mode: manifest fields ---'

evidence_dir="${WORK_DIR}/evidence/mytest"
mkdir -p "$evidence_dir"

HOOK_EXIT=0
RND_EVIDENCE_PACK=1 RND_DIR="$WORK_DIR" RND_TASK_ID="mytest" \
  bash "$RUN_TOOL" -- printf '%s' "packed" >"${WORK_DIR}/cmd_stdout.txt" 2>/dev/null || HOOK_EXIT=$?

assert_eq "pack mode: exit code propagated (0)" "0" "$HOOK_EXIT"

manifest="${evidence_dir}/manifest.json"
assert_eq "pack mode: manifest.json exists" "true" "$([[ -f "$manifest" ]] && echo true || echo false)"

HAS_TOOL="$(jq 'has("tool")' "$manifest")"
assert_eq "manifest has 'tool' field" "true" "$HAS_TOOL"

HAS_ARGV="$(jq 'has("command_argv")' "$manifest")"
assert_eq "manifest has 'command_argv' field" "true" "$HAS_ARGV"

HAS_CWD="$(jq 'has("cwd")' "$manifest")"
assert_eq "manifest has 'cwd' field" "true" "$HAS_CWD"

HAS_STARTED="$(jq 'has("started_at")' "$manifest")"
assert_eq "manifest has 'started_at' field" "true" "$HAS_STARTED"

HAS_FINISHED="$(jq 'has("finished_at")' "$manifest")"
assert_eq "manifest has 'finished_at' field" "true" "$HAS_FINISHED"

HAS_EXIT="$(jq 'has("exit_code")' "$manifest")"
assert_eq "manifest has 'exit_code' field" "true" "$HAS_EXIT"

EXIT_IS_INT="$(jq '.exit_code | type == "number"' "$manifest")"
assert_eq "manifest exit_code is integer" "true" "$EXIT_IS_INT"

HAS_STDOUT="$(jq 'has("stdout_path")' "$manifest")"
assert_eq "manifest has 'stdout_path' field" "true" "$HAS_STDOUT"

HAS_STDERR="$(jq 'has("stderr_path")' "$manifest")"
assert_eq "manifest has 'stderr_path' field" "true" "$HAS_STDERR"

HAS_INPUTS="$(jq 'has("inputs")' "$manifest")"
assert_eq "manifest has 'inputs' field" "true" "$HAS_INPUTS"

INPUTS_IS_ARRAY="$(jq '.inputs | type == "array"' "$manifest")"
assert_eq "manifest inputs is array" "true" "$INPUTS_IS_ARRAY"

ARGV_IS_ARRAY="$(jq '.command_argv | type == "array"' "$manifest")"
assert_eq "manifest command_argv is array" "true" "$ARGV_IS_ARRAY"

# ---------------------------------------------------------------------------
# Pack mode: input hash format (64-char hex)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pack mode: input hash format ---'

INPUT_COUNT="$(jq '.inputs | length' "$manifest")"
if [[ "$INPUT_COUNT" -gt 0 ]]; then
  ALL_HASHES_VALID="$(jq '[.inputs[] | .sha256 | test("^[0-9a-f]{64}$")] | all' "$manifest")"
  assert_eq "all inputs[] sha256 are 64-char hex" "true" "$ALL_HASHES_VALID"

  ALL_HAVE_PATH="$(jq '[.inputs[] | has("path")] | all' "$manifest")"
  assert_eq "all inputs[] have path field" "true" "$ALL_HAVE_PATH"
else
  assert_eq "inputs array present (may be empty if no git repo)" "true" "true"
fi

# ---------------------------------------------------------------------------
# Pack mode: skip-list paths not in inputs (real git repo test)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pack mode: skip-list exclusion ---'

# Set up a real git repo with tracked files inside root-level skip-list dirs.
skip_git_dir="${WORK_DIR}/skip-test-repo"
mkdir -p "$skip_git_dir"
git -C "$skip_git_dir" init -q
git -C "$skip_git_dir" config user.email "test@test.com"
git -C "$skip_git_dir" config user.name "Test"

# Create a tracked source file and files inside each skip-list dir at the root.
mkdir -p \
  "${skip_git_dir}/node_modules/dep" \
  "${skip_git_dir}/_build" \
  "${skip_git_dir}/deps" \
  "${skip_git_dir}/.venv" \
  "${skip_git_dir}/target" \
  "${skip_git_dir}/dist"

printf 'hello' > "${skip_git_dir}/source.txt"
printf '{}' > "${skip_git_dir}/node_modules/dep.json"
printf '{}' > "${skip_git_dir}/_build/out"
printf '{}' > "${skip_git_dir}/deps/dep.ex"
printf '{}' > "${skip_git_dir}/.venv/pyvenv.cfg"
printf '{}' > "${skip_git_dir}/target/app.beam"
printf '{}' > "${skip_git_dir}/dist/bundle.js"

# Stage and commit all files so git ls-files returns them.
git -C "$skip_git_dir" add -A
git -C "$skip_git_dir" commit -q -m "init"

skip_evidence_dir="${WORK_DIR}/evidence/skip-test"
mkdir -p "$skip_evidence_dir"

# Run run-tool.sh from within the test repo so git ls-files picks up the repo.
(
  cd "$skip_git_dir"
  RND_EVIDENCE_PACK=1 RND_DIR="$WORK_DIR" RND_TASK_ID="skip-test" \
    bash "$RUN_TOOL" -- printf '' 2>/dev/null
)

skip_manifest="${skip_evidence_dir}/manifest.json"

assert_eq "skip-list test: manifest.json written" "true" "$([[ -f "$skip_manifest" ]] && echo true || echo false)"

# Assert that none of the skip-list directory paths appear in inputs[].
SKIP_NODES="$(jq '[.inputs[].path | test("^node_modules(/|$)")] | any' "$skip_manifest")"
assert_eq "skip-list: node_modules at root excluded from inputs" "false" "$SKIP_NODES"

SKIP_BUILD="$(jq '[.inputs[].path | test("^_build(/|$)")] | any' "$skip_manifest")"
assert_eq "skip-list: _build at root excluded from inputs" "false" "$SKIP_BUILD"

SKIP_DEPS="$(jq '[.inputs[].path | test("^deps(/|$)")] | any' "$skip_manifest")"
assert_eq "skip-list: deps at root excluded from inputs" "false" "$SKIP_DEPS"

SKIP_VENV="$(jq '[.inputs[].path | test("^[.]venv(/|$)")] | any' "$skip_manifest")"
assert_eq "skip-list: .venv at root excluded from inputs" "false" "$SKIP_VENV"

SKIP_TARGET="$(jq '[.inputs[].path | test("^target(/|$)")] | any' "$skip_manifest")"
assert_eq "skip-list: target at root excluded from inputs" "false" "$SKIP_TARGET"

SKIP_DIST="$(jq '[.inputs[].path | test("^dist(/|$)")] | any' "$skip_manifest")"
assert_eq "skip-list: dist at root excluded from inputs" "false" "$SKIP_DIST"

# Verify the source file IS included (i.e., skip only applies to skip dirs, not all files).
SOURCE_IN="$(jq '[.inputs[].path | test("^source[.]txt$")] | any' "$skip_manifest")"
assert_eq "skip-list: non-skip source.txt is included in inputs" "true" "$SOURCE_IN"

# ---------------------------------------------------------------------------
# Pack mode: non-zero exit code propagated
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pack mode: exit code propagation ---'

evidence_dir2="${WORK_DIR}/evidence/failing"
mkdir -p "$evidence_dir2"

HOOK_EXIT=0
RND_EVIDENCE_PACK=1 RND_DIR="$WORK_DIR" RND_TASK_ID="failing" \
  bash "$RUN_TOOL" -- bash -c 'exit 7' 2>/dev/null || HOOK_EXIT=$?

assert_eq "pack mode: non-zero exit code propagated" "7" "$HOOK_EXIT"

manifest2="${evidence_dir2}/manifest.json"
EXIT_IN_MANIFEST="$(jq '.exit_code' "$manifest2")"
assert_eq "pack mode: exit_code in manifest matches command exit" "7" "$EXIT_IN_MANIFEST"

# ---------------------------------------------------------------------------
# Project override: $RND_DIR/tools.json keys win on conflict
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- project override for tools.json ---'

override_dir="${WORK_DIR}/override-test"
mkdir -p "${override_dir}/evidence/override-task"

# Write a project-level tools.json that overrides pytest structured_flags
jq -n '{"pytest": {"structured_flags": ["--custom-override-flag"], "structured_ext": "txt"}}' \
  > "${override_dir}/tools.json"

# Run in a sub-shell to inspect structured flags loading (check that merged config contains override)
merged_flags="$(RND_EVIDENCE_PACK=1 RND_DIR="$override_dir" RND_TASK_ID="override-task" \
  bash -c "
    SCRIPT_DIR=\"${PLUGIN_DIR}/lib\"
    plugin_tools_json=\"\${SCRIPT_DIR}/tools.json\"
    project_tools_json=\"${override_dir}/tools.json\"
    merged=\$(cat \"\$plugin_tools_json\")
    merged=\$(printf '%s\n%s' \"\$merged\" \"\$(cat \"\$project_tools_json\")\" | jq -s '.[0] * .[1]')
    printf '%s' \"\$merged\" | jq -r '.pytest.structured_flags[0]'
  ")"

assert_eq "project override wins: pytest.structured_flags[0]" "--custom-override-flag" "$merged_flags"

# Default (plugin) key not present in override file remains intact
merged_jest_ext="$(RND_EVIDENCE_PACK=1 RND_DIR="$override_dir" \
  bash -c "
    SCRIPT_DIR=\"${PLUGIN_DIR}/lib\"
    plugin_tools_json=\"\${SCRIPT_DIR}/tools.json\"
    project_tools_json=\"${override_dir}/tools.json\"
    merged=\$(cat \"\$plugin_tools_json\")
    merged=\$(printf '%s\n%s' \"\$merged\" \"\$(cat \"\$project_tools_json\")\" | jq -s '.[0] * .[1]')
    printf '%s' \"\$merged\" | jq -r '.jest.structured_ext'
  ")"

assert_eq "project override: jest.structured_ext from plugin default preserved" "json" "$merged_jest_ext"

# ---------------------------------------------------------------------------
# --help / usage output
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- --help flag ---'

HOOK_EXIT=0
help_out="$(bash "$RUN_TOOL" --help 2>&1)" || HOOK_EXIT=$?
assert_eq "--help exits 0" "0" "$HOOK_EXIT"
assert_contains "--help shows Usage:" "Usage:" "$help_out"

# no-args also shows usage
HOOK_EXIT=0
noarg_out="$(bash "$RUN_TOOL" 2>&1)" || HOOK_EXIT=$?
assert_eq "no-args exits 0" "0" "$HOOK_EXIT"
assert_contains "no-args shows Usage:" "Usage:" "$noarg_out"

# ---------------------------------------------------------------------------
# Pack mode: audit.jsonl emission
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- pack mode: audit.jsonl emission ---'

audit_dir="${WORK_DIR}/audit-test"
mkdir -p "${audit_dir}/evidence/audit-task"

RND_EVIDENCE_PACK=1 RND_DIR="$audit_dir" RND_TASK_ID="audit-task" \
  bash "$RUN_TOOL" -- printf '' 2>/dev/null

AUDIT_EXISTS="$([[ -f "${audit_dir}/audit.jsonl" ]] && echo true || echo false)"
assert_eq "audit.jsonl is created after pack run" "true" "$AUDIT_EXISTS"

AUDIT_VALID_JSON="$(jq '.' "${audit_dir}/audit.jsonl" >/dev/null 2>&1 && echo true || echo false)"
assert_eq "audit.jsonl last line is valid JSON" "true" "$AUDIT_VALID_JSON"

AUDIT_EVENT="$(jq -r '.event' "${audit_dir}/audit.jsonl")"
assert_eq "audit event is tool_run_fresh" "tool_run_fresh" "$AUDIT_EVENT"

AUDIT_HAS_TASK_ID="$(jq 'has("task_id")' "${audit_dir}/audit.jsonl")"
assert_eq "audit line has task_id field" "true" "$AUDIT_HAS_TASK_ID"

AUDIT_TASK_ID="$(jq -r '.task_id' "${audit_dir}/audit.jsonl")"
assert_eq "audit task_id matches RND_TASK_ID" "audit-task" "$AUDIT_TASK_ID"

AUDIT_HAS_TOOL="$(jq 'has("tool")' "${audit_dir}/audit.jsonl")"
assert_eq "audit line has tool field" "true" "$AUDIT_HAS_TOOL"

AUDIT_HAS_TS="$(jq 'has("timestamp")' "${audit_dir}/audit.jsonl")"
assert_eq "audit line has timestamp field" "true" "$AUDIT_HAS_TS"

# ---------------------------------------------------------------------------
# relevant_globs in tools.json (M1: per-tool input scoping)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- relevant_globs registry ---'

for tool in pytest jest vitest tsc eslint mypy dialyzer bun cargo mix ruff biome; do
  HAS_GLOBS="$(jq --arg t "$tool" '.[$t].relevant_globs | type == "array" and (length > 0)' "$TOOLS_JSON")"
  assert_eq "tools.json[$tool].relevant_globs is non-empty array" "true" "$HAS_GLOBS"
done

# ---------------------------------------------------------------------------
# Glob-filtered inputs[] (M1: pytest run only hashes Python-relevant files)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- glob-filtered inputs[] ---'

GLOB_REPO="${WORK_DIR}/glob-repo"
mkdir -p "$GLOB_REPO"
( cd "$GLOB_REPO" \
  && git init -q \
  && git config user.email t@e \
  && git config user.name t \
  && printf 'print(1)\n' > a.py \
  && printf 'print(2)\n' > b.py \
  && printf 'console.log(3)\n' > c.js \
  && printf 'console.log(4)\n' > d.ts \
  && printf '[tool.pytest]\n' > pyproject.toml \
  && printf '# readme\n' > README.md \
  && git add -A && git commit -q -m init )

# Fake pytest binary that just exits 0 without doing anything
FAKE_PYTEST_DIR="${WORK_DIR}/fake-pytest"
mkdir -p "$FAKE_PYTEST_DIR"
cat > "${FAKE_PYTEST_DIR}/pytest" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${FAKE_PYTEST_DIR}/pytest"

GLOB_RND="${WORK_DIR}/glob-rnd"
mkdir -p "$GLOB_RND"

(
  cd "$GLOB_REPO"
  PATH="${FAKE_PYTEST_DIR}:$PATH" RND_EVIDENCE_PACK=1 RND_DIR="$GLOB_RND" \
    bash "$RUN_TOOL" --task-id glob-test -- pytest >/dev/null 2>&1
)

GLOB_MANIFEST="${GLOB_RND}/evidence/glob-test/manifest.json"

# Pytest globs include *.py and pyproject.toml — so a.py, b.py, pyproject.toml in inputs
PY_COUNT="$(jq '[.inputs[].path | select(test("\\.py$"))] | length' "$GLOB_MANIFEST")"
assert_eq "pytest run: a.py and b.py present in inputs" "2" "$PY_COUNT"

PYPROJECT_PRESENT="$(jq '[.inputs[].path | select(. == "pyproject.toml")] | length' "$GLOB_MANIFEST")"
assert_eq "pytest run: pyproject.toml present in inputs" "1" "$PYPROJECT_PRESENT"

# *.js, *.ts, README.md must NOT be included for pytest
JS_PRESENT="$(jq '[.inputs[].path | select(test("\\.js$|\\.ts$"))] | length' "$GLOB_MANIFEST")"
assert_eq "pytest run: c.js and d.ts NOT in inputs" "0" "$JS_PRESENT"

README_PRESENT="$(jq '[.inputs[].path | select(. == "README.md")] | length' "$GLOB_MANIFEST")"
assert_eq "pytest run: README.md NOT in inputs" "0" "$README_PRESENT"

# Unknown tool (echo) → no glob narrowing → all 5 tracked files in inputs
UNKNOWN_RND="${WORK_DIR}/unknown-rnd"
mkdir -p "$UNKNOWN_RND"
(
  cd "$GLOB_REPO"
  RND_EVIDENCE_PACK=1 RND_DIR="$UNKNOWN_RND" \
    bash "$RUN_TOOL" --task-id unknown-test -- echo hello >/dev/null 2>&1
)
UNKNOWN_MANIFEST="${UNKNOWN_RND}/evidence/unknown-test/manifest.json"
ALL_COUNT="$(jq '.inputs | length' "$UNKNOWN_MANIFEST")"
assert_eq "unknown tool: all 6 tracked files in inputs (no narrowing)" "6" "$ALL_COUNT"

# ---------------------------------------------------------------------------
# audit-event.sh shared helper
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- audit-event.sh helper ---'

AUDIT_HELPER="${PLUGIN_DIR}/lib/audit-event.sh"
AE_DIR="${WORK_DIR}/audit-helper"
mkdir -p "$AE_DIR"

# Missing args → exit 1
AE_NOARGS_EXIT=0
bash "$AUDIT_HELPER" >/dev/null 2>&1 || AE_NOARGS_EXIT=$?
assert_eq "audit-event.sh with no args exits 1" "1" "$AE_NOARGS_EXIT"

# Missing RND_DIR → exit 1
AE_NORND_EXIT=0
( unset RND_DIR; bash "$AUDIT_HELPER" tool_pack_served T1 pytest >/dev/null 2>&1 ) || AE_NORND_EXIT=$?
assert_eq "audit-event.sh without RND_DIR exits 1" "1" "$AE_NORND_EXIT"

# Happy path: writes a single line with all 4 fields and the given event
RND_DIR="$AE_DIR" bash "$AUDIT_HELPER" tool_pack_served T7 pytest
AE_LINES="$(wc -l < "${AE_DIR}/audit.jsonl" | tr -d ' ')"
assert_eq "audit-event.sh writes one line" "1" "$AE_LINES"

AE_EVENT="$(jq -r '.event' "${AE_DIR}/audit.jsonl")"
assert_eq "audit-event.sh: event field = tool_pack_served" "tool_pack_served" "$AE_EVENT"

AE_TASK="$(jq -r '.task_id' "${AE_DIR}/audit.jsonl")"
assert_eq "audit-event.sh: task_id = T7" "T7" "$AE_TASK"

AE_TOOL="$(jq -r '.tool' "${AE_DIR}/audit.jsonl")"
assert_eq "audit-event.sh: tool = pytest" "pytest" "$AE_TOOL"

AE_HAS_TS="$(jq 'has("timestamp")' "${AE_DIR}/audit.jsonl")"
assert_eq "audit-event.sh: timestamp field present" "true" "$AE_HAS_TS"

# Append behavior: second call appends, doesn't overwrite
RND_DIR="$AE_DIR" bash "$AUDIT_HELPER" tool_run_fresh T8 jest
AE_LINES2="$(wc -l < "${AE_DIR}/audit.jsonl" | tr -d ' ')"
assert_eq "audit-event.sh appends (line count = 2)" "2" "$AE_LINES2"

# ---------------------------------------------------------------------------
# task-id sanitization (m2 fix)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- task-id sanitization ---'

# Path traversal attempt → rejected with exit 1
TRAVERSAL_EXIT=0
bash "$RUN_TOOL" --task-id '../escape' -- echo hi >/dev/null 2>&1 || TRAVERSAL_EXIT=$?
assert_eq "task-id with .. is rejected (exit 1)" "1" "$TRAVERSAL_EXIT"

# Slash in task-id → rejected
SLASH_EXIT=0
bash "$RUN_TOOL" --task-id 'a/b' -- echo hi >/dev/null 2>&1 || SLASH_EXIT=$?
assert_eq "task-id with / is rejected (exit 1)" "1" "$SLASH_EXIT"

# Valid task-id (alphanumeric + dash + underscore) → accepted
VALID_EXIT=0
bash "$RUN_TOOL" --task-id 'T1_test-42' -- printf '' >/dev/null 2>&1 || VALID_EXIT=$?
assert_eq "task-id with [A-Za-z0-9_-]+ is accepted" "0" "$VALID_EXIT"

# ---------------------------------------------------------------------------
report
