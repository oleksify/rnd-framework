#!/usr/bin/env bash
# tests/run-properties.test.sh — Tests for lib/run-properties.sh.
# Exercises: passing fixture, counter-example fixture, skipped (runtime absent).
# Usage: bash tests/run-properties.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER="${PLUGIN_ROOT}/lib/run-properties.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Setup: stub executables in $RND_DIR/test-stubs (never /tmp).
# ---------------------------------------------------------------------------
RND_DIR="${RND_DIR:-${HOME}/.claude/.rnd/run-properties-test-$$}"
STUB_DIR="${RND_DIR}/run-properties-stubs"
mkdir -p "$STUB_DIR"

# Cleanup on exit.
trap 'rm -rf "$STUB_DIR"' EXIT

# Real StreamData 1.3.0 / ExUnit counter-example output (verbatim format).
# Property keyword, Clause/Generated format — no "Shrunk:" section.
ELIXIR_FAIL_OUTPUT='Running ExUnit with seed: 518161, max_cases: 32
Including tags: [:property]



  1) property prop_list_length is always negative (PropTestTest)
     test/prop_test_test.exs:6
     Failed with generated values (after 0 successful runs):

         * Clause:    list <- list_of(integer())
           Generated: []

     Assertion with < failed, both sides are exactly equal
     code: assert length(list) < 0
     left: 0
     stacktrace:
       test/prop_test_test.exs:9: anonymous fn/2 in PropTestTest."property prop_list_length is always negative"/1
       (stream_data 1.3.0) lib/stream_data.ex:2556: StreamData.shrink_failure/6
       (stream_data 1.3.0) lib/stream_data.ex:2516: StreamData.check_all/7
       test/prop_test_test.exs:7: (test)


Finished in 0.01 seconds (0.00s async, 0.01s sync)
1 property, 1 failure'

# Real bun 1.3.14 + fast-check 3.23.2 counter-example output (verbatim format).
# "(fail)" marker, negative seed, Counterexample line.
TYPESCRIPT_FAIL_OUTPUT='bun test v1.3.14 (0d9b296a)

prop.test.ts:
121 |     }
122 |     return defaultReportMessageInternal(out, stringifySecond);
error: Property failed after 1 tests
{ seed: -1875452357, path: "0:0", endOnFailure: true }
Counterexample: [[]]
Shrunk 1 time(s)
Got error: expect(received).toBeLessThan(expected)

(fail) prop_list_length is always negative [2.39ms]

 0 pass
 1 fail'

# Write stub helpers; $1 = script path, $2 = exit code, $3 = stdout text.
_write_stub() {
  local path="$1" code="$2" output="$3"
  printf '#!/usr/bin/env bash\nprintf "%%s\n" %s\nexit %d\n' \
    "$(printf '%q' "$output")" "$code" > "$path"
  chmod +x "$path"
}

STUB_MIX="${STUB_DIR}/mix"
STUB_BUN="${STUB_DIR}/bun"
FIXTURE="${STUB_DIR}/fixture.exs"
printf '' > "$FIXTURE"

# ---------------------------------------------------------------------------
# Helper: run the runner with the stub dir prepended to PATH.
# ---------------------------------------------------------------------------
_run() {
  local lang="$1" fixture="$2"
  local stdout_file stderr_file
  stdout_file="${STUB_DIR}/stdout.txt"
  stderr_file="${STUB_DIR}/stderr.txt"
  HOOK_EXIT=0
  PATH="${STUB_DIR}:${PATH}" \
    "$RUNNER" "$lang" "$fixture" "$STUB_DIR" \
    > "$stdout_file" 2> "$stderr_file" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
}

# ---------------------------------------------------------------------------
# Criterion: file exists, is executable, has shebang + pipefail.
# ---------------------------------------------------------------------------
printf '\n--- file: exists, executable, shebang, pipefail ---\n'

assert_eq "runner file exists" "yes" "$(test -f "$RUNNER" && printf yes || printf no)"
assert_eq "runner is executable" "yes" "$(test -x "$RUNNER" && printf yes || printf no)"
assert_eq "line 1 is shebang" '#!/usr/bin/env bash' \
  "$(head -1 "$RUNNER")"
assert_eq "line 2 is pipefail" 'set -euo pipefail' \
  "$(head -2 "$RUNNER" | tail -1)"

# ---------------------------------------------------------------------------
# Criterion: dispatch is a single case statement (no sub-scripts).
# ---------------------------------------------------------------------------
printf '\n--- quality: single case dispatch ---\n'

case_count="$(grep -c '^case "\$lang" in' "$RUNNER" || true)"
assert_eq "exactly one case dispatch" "1" "$case_count"

# ---------------------------------------------------------------------------
# Criterion: elixir pass → PROPERTY_PASS, exit 0.
# ---------------------------------------------------------------------------
printf '\n--- elixir: passing fixture → PROPERTY_PASS ---\n'

_write_stub "$STUB_MIX" 0 ""
_run elixir "$FIXTURE"

assert_eq "elixir pass: exit 0" "0" "$HOOK_EXIT"
assert_contains "elixir pass: stdout contains PROPERTY_PASS" \
  "PROPERTY_PASS" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Criterion: typescript pass → PROPERTY_PASS, exit 0.
# ---------------------------------------------------------------------------
printf '\n--- typescript: passing fixture → PROPERTY_PASS ---\n'

_write_stub "$STUB_BUN" 0 ""
_run typescript "${STUB_DIR}/fixture.test.ts"

assert_eq "typescript pass: exit 0" "0" "$HOOK_EXIT"
assert_contains "typescript pass: stdout contains PROPERTY_PASS" \
  "PROPERTY_PASS" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Criterion: elixir counter-example → PROPERTY_COUNTER_EXAMPLE, stderr JSON.
# ---------------------------------------------------------------------------
printf '\n--- elixir: counter-example fixture → PROPERTY_COUNTER_EXAMPLE + JSON ---\n'

_write_stub "$STUB_MIX" 1 "$ELIXIR_FAIL_OUTPUT"
_run elixir "$FIXTURE"

assert_contains "elixir counter-example: stdout contains PROPERTY_COUNTER_EXAMPLE" \
  "PROPERTY_COUNTER_EXAMPLE" "$HOOK_STDOUT"

assert_eq "elixir counter-example: exit non-zero" "1" "$HOOK_EXIT"

# Validate stderr is parseable JSON
elixir_json_valid="$(printf '%s' "$HOOK_STDERR" | jq -e . > /dev/null 2>&1 && printf yes || printf no)"
assert_eq "elixir counter-example: stderr is valid JSON" "yes" "$elixir_json_valid"

# Check required keys
elixir_has_property="$(printf '%s' "$HOOK_STDERR" | jq 'has("property")' 2>/dev/null || printf false)"
assert_eq "elixir counter-example: JSON has property key" "true" "$elixir_has_property"

elixir_has_shrunk="$(printf '%s' "$HOOK_STDERR" | jq 'has("shrunk_input")' 2>/dev/null || printf false)"
assert_eq "elixir counter-example: JSON has shrunk_input key" "true" "$elixir_has_shrunk"

elixir_has_seed="$(printf '%s' "$HOOK_STDERR" | jq 'has("seed")' 2>/dev/null || printf false)"
assert_eq "elixir counter-example: JSON has seed key" "true" "$elixir_has_seed"

# Check extracted values match the real StreamData output format
elixir_prop="$(printf '%s' "$HOOK_STDERR" | jq -r '.property' 2>/dev/null || printf '')"
assert_eq "elixir counter-example: property name extracted" "prop_list_length is always negative" "$elixir_prop"

elixir_shrunk="$(printf '%s' "$HOOK_STDERR" | jq -r '.shrunk_input' 2>/dev/null || printf '')"
assert_eq "elixir counter-example: shrunk_input extracted" "[]" "$elixir_shrunk"

elixir_seed="$(printf '%s' "$HOOK_STDERR" | jq -r '.seed' 2>/dev/null || printf '')"
assert_eq "elixir counter-example: seed extracted" "518161" "$elixir_seed"

# ---------------------------------------------------------------------------
# Criterion: typescript counter-example → PROPERTY_COUNTER_EXAMPLE, stderr JSON.
# ---------------------------------------------------------------------------
printf '\n--- typescript: counter-example fixture → PROPERTY_COUNTER_EXAMPLE + JSON ---\n'

_write_stub "$STUB_BUN" 1 "$TYPESCRIPT_FAIL_OUTPUT"
_run typescript "${STUB_DIR}/fixture.test.ts"

assert_contains "typescript counter-example: stdout contains PROPERTY_COUNTER_EXAMPLE" \
  "PROPERTY_COUNTER_EXAMPLE" "$HOOK_STDOUT"

assert_eq "typescript counter-example: exit non-zero" "1" "$HOOK_EXIT"

ts_json_valid="$(printf '%s' "$HOOK_STDERR" | jq -e . > /dev/null 2>&1 && printf yes || printf no)"
assert_eq "typescript counter-example: stderr is valid JSON" "yes" "$ts_json_valid"

ts_has_property="$(printf '%s' "$HOOK_STDERR" | jq 'has("property")' 2>/dev/null || printf false)"
assert_eq "typescript counter-example: JSON has property key" "true" "$ts_has_property"

ts_has_shrunk="$(printf '%s' "$HOOK_STDERR" | jq 'has("shrunk_input")' 2>/dev/null || printf false)"
assert_eq "typescript counter-example: JSON has shrunk_input key" "true" "$ts_has_shrunk"

ts_has_seed="$(printf '%s' "$HOOK_STDERR" | jq 'has("seed")' 2>/dev/null || printf false)"
assert_eq "typescript counter-example: JSON has seed key" "true" "$ts_has_seed"

ts_prop="$(printf '%s' "$HOOK_STDERR" | jq -r '.property' 2>/dev/null || printf '')"
assert_eq "typescript counter-example: property name extracted" "prop_list_length is always negative" "$ts_prop"

ts_shrunk="$(printf '%s' "$HOOK_STDERR" | jq -r '.shrunk_input' 2>/dev/null || printf '')"
assert_eq "typescript counter-example: shrunk_input extracted" "[[]]" "$ts_shrunk"

ts_seed="$(printf '%s' "$HOOK_STDERR" | jq -r '.seed' 2>/dev/null || printf '')"
assert_eq "typescript counter-example: seed extracted as signed integer" "-1875452357" "$ts_seed"

# ---------------------------------------------------------------------------
# Criterion: runtime absent → PROPERTY_SKIPPED missing-runtime: <tool>, exit 0.
# ---------------------------------------------------------------------------
printf '\n--- skip: runtime absent (PATH cleared) ---\n'

# Remove stubs so the runner finds neither mix nor bun.
rm -f "$STUB_MIX" "$STUB_BUN"

_elixir_skip() {
  local stdout_file stderr_file
  stdout_file="${STUB_DIR}/stdout.txt"
  stderr_file="${STUB_DIR}/stderr.txt"
  HOOK_EXIT=0
  PATH="/usr/bin:/bin" \
    "$RUNNER" elixir "$FIXTURE" "$STUB_DIR" \
    > "$stdout_file" 2> "$stderr_file" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
}

_typescript_skip() {
  local stdout_file stderr_file
  stdout_file="${STUB_DIR}/stdout.txt"
  stderr_file="${STUB_DIR}/stderr.txt"
  HOOK_EXIT=0
  PATH="/usr/bin:/bin" \
    "$RUNNER" typescript "${STUB_DIR}/fixture.test.ts" "$STUB_DIR" \
    > "$stdout_file" 2> "$stderr_file" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
}

_elixir_skip
assert_eq "elixir skip: exit 0" "0" "$HOOK_EXIT"
assert_contains "elixir skip: stdout contains PROPERTY_SKIPPED" \
  "PROPERTY_SKIPPED missing-runtime:" "$HOOK_STDOUT"
assert_contains "elixir skip: tool name is mix" \
  "mix" "$HOOK_STDOUT"

_typescript_skip
assert_eq "typescript skip: exit 0" "0" "$HOOK_EXIT"
assert_contains "typescript skip: stdout contains PROPERTY_SKIPPED" \
  "PROPERTY_SKIPPED missing-runtime:" "$HOOK_STDOUT"
assert_contains "typescript skip: tool name is bun" \
  "bun" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Criterion: schema pass → PROPERTY_PASS, exit 0.
# ---------------------------------------------------------------------------
printf '\n--- schema: passing fixture → PROPERTY_PASS ---\n'

SCHEMA_PASS_FIXTURE="${STUB_DIR}/schema-pass.json"
printf '{"required":["id","name"],"sample":{"id":1,"name":"Alice"}}\n' > "$SCHEMA_PASS_FIXTURE"

_run_schema() {
  local fixture="$1"
  local stdout_file stderr_file
  stdout_file="${STUB_DIR}/stdout.txt"
  stderr_file="${STUB_DIR}/stderr.txt"
  HOOK_EXIT=0
  "$RUNNER" schema "$fixture" "$STUB_DIR" \
    > "$stdout_file" 2> "$stderr_file" || HOOK_EXIT=$?
  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
}

_run_schema "$SCHEMA_PASS_FIXTURE"
assert_eq "schema pass: exit 0" "0" "$HOOK_EXIT"
assert_contains "schema pass: stdout contains PROPERTY_PASS" "PROPERTY_PASS" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Criterion: schema fail → PROPERTY_COUNTER_EXAMPLE + stderr JSON.
# ---------------------------------------------------------------------------
printf '\n--- schema: failing fixture → PROPERTY_COUNTER_EXAMPLE + JSON ---\n'

SCHEMA_FAIL_FIXTURE="${STUB_DIR}/schema-fail.json"
printf '{"required":["id","name"],"sample":{"id":1}}\n' > "$SCHEMA_FAIL_FIXTURE"

_run_schema "$SCHEMA_FAIL_FIXTURE"
assert_contains "schema fail: stdout contains PROPERTY_COUNTER_EXAMPLE" \
  "PROPERTY_COUNTER_EXAMPLE" "$HOOK_STDOUT"
assert_eq "schema fail: exit non-zero" "1" "$HOOK_EXIT"

schema_json_valid="$(printf '%s' "$HOOK_STDERR" | jq -e . > /dev/null 2>&1 && printf yes || printf no)"
assert_eq "schema fail: stderr is valid JSON" "yes" "$schema_json_valid"

schema_missing="$(printf '%s' "$HOOK_STDERR" | jq -r '.shrunk_input' 2>/dev/null || printf '')"
assert_eq "schema fail: missing field identified" "name" "$schema_missing"

schema_has_property="$(printf '%s' "$HOOK_STDERR" | jq 'has("property")' 2>/dev/null || printf false)"
assert_eq "schema fail: JSON has property key" "true" "$schema_has_property"

schema_has_seed="$(printf '%s' "$HOOK_STDERR" | jq 'has("seed")' 2>/dev/null || printf false)"
assert_eq "schema fail: JSON has seed key" "true" "$schema_has_seed"

# ---------------------------------------------------------------------------
# Criterion: malformed schema fixture → non-zero exit + diagnostic (no false PASS).
# Guards against the regression where `missing="$(jq ...)"` silently swallows
# jq failure under `set -e` and the script reports PROPERTY_PASS on a fixture
# that was never validly parsed.
# ---------------------------------------------------------------------------
printf '\n--- schema: malformed fixture → exit 2 + diagnostic ---\n'

SCHEMA_BAD_FIXTURE="${STUB_DIR}/schema-malformed.json"
printf '{ "required": [ "id"   ::: NOT JSON' > "$SCHEMA_BAD_FIXTURE"

_run_schema "$SCHEMA_BAD_FIXTURE"
assert_eq "schema malformed: exit 2 (not 0)" "2" "$HOOK_EXIT"
property_pass_emitted="$(printf '%s' "$HOOK_STDOUT" | grep -c 'PROPERTY_PASS' || true)"
assert_eq "schema malformed: no false PROPERTY_PASS in stdout" "0" "$property_pass_emitted"
assert_contains "schema malformed: stderr names the fixture path" \
  "$SCHEMA_BAD_FIXTURE" "$HOOK_STDERR"
assert_contains "schema malformed: stderr mentions invalid JSON" \
  "not valid JSON" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# Criterion: --help and unknown lang print usage.
# ---------------------------------------------------------------------------
printf '\n--- help flag and unknown lang ---\n'

help_out="$("$RUNNER" --help 2>&1 || true)"
assert_contains "--help prints usage" "Usage:" "$help_out"
assert_contains "--help prints lang values" "elixir" "$help_out"
assert_contains "--help prints lang values" "typescript" "$help_out"
assert_contains "--help mentions schema" "schema" "$help_out"

unknown_out="$("$RUNNER" invalid-lang /dev/null /dev/null 2>&1 || true)"
assert_contains "unknown lang prints usage" "Usage:" "$unknown_out"
assert_contains "unknown lang mentions elixir" "elixir" "$unknown_out"

# ---------------------------------------------------------------------------
# Criterion: stderr JSON built via jq -nc (not hand-rolled).
# ---------------------------------------------------------------------------
printf '\n--- quality: jq -nc usage in runner ---\n'

jq_nc_count="$(grep -c 'jq -nc' "$RUNNER" || true)"
assert_eq "runner uses jq -nc" "yes" "$([ "$jq_nc_count" -ge 1 ] && printf yes || printf no)"

report
