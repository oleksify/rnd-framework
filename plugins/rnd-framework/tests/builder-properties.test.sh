#!/usr/bin/env bash
# tests/builder-properties.test.sh — Tests for Builder-side property execution.
#
# Verifies that:
#   1. run-properties.sh can be invoked and produces output (schema lang used as
#      a runtime-agnostic stand-in since mix/bun may be absent in CI).
#   2. The output path embeds "self-assessment" so the existing read-gate barrier
#      blocks Verifier reads without any change to the hook predicate.
#   3. read-gate.sh actually blocks a Verifier read of the output path.
#   4. read-gate.sh allows a Builder read of the same path (exit 0).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

HOOK="${SCRIPT_DIR}/../hooks/read-gate.sh"
RUN_PROPS="${SCRIPT_DIR}/../lib/run-properties.sh"

printf '%s\n' '--- builder-side property execution ---'

# ---------------------------------------------------------------------------
# Setup: temp dirs acting as $RND_DIR/builds/ and project dir
# ---------------------------------------------------------------------------

tmp_rnd_dir="$(mktemp -d)"
tmp_project_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_rnd_dir" "$tmp_project_dir"' EXIT

builds_dir="${tmp_rnd_dir}/builds"
mkdir -p "$builds_dir"

# The output path: contains "self-assessment" so the existing read-gate barrier
# covers it without any predicate change.
output_path="${builds_dir}/T99-self-assessment-properties.txt"

# Create a minimal valid schema fixture (lang=schema is runtime-agnostic).
schema_fixture="${tmp_project_dir}/props.json"
printf '%s\n' '{"required":["name","value"],"sample":{"name":"test","value":42}}' \
  > "$schema_fixture"

# ---------------------------------------------------------------------------
# 1. run-properties.sh writes PROPERTY_PASS output to the designated path
# ---------------------------------------------------------------------------

"$RUN_PROPS" schema "$schema_fixture" "$tmp_project_dir" > "$output_path" 2>&1 || true

if [[ -f "$output_path" ]]; then
  assert_eq "output file created at barrier-protected path" "exists" "exists"
else
  assert_eq "output file created at barrier-protected path" "exists" "missing"
fi

if [[ -s "$output_path" ]]; then
  assert_eq "output file is non-empty" "non-empty" "non-empty"
else
  assert_eq "output file is non-empty" "non-empty" "empty"
fi

output_content="$(cat "$output_path")"
assert_contains "output contains PROPERTY_PASS" "PROPERTY_PASS" "$output_content"

# ---------------------------------------------------------------------------
# 2. Path contains "self-assessment" — barrier predicate covers it
# ---------------------------------------------------------------------------

if [[ "$output_path" == *"self-assessment"* ]]; then
  assert_eq "output path embeds self-assessment (barrier pattern)" "matched" "matched"
else
  assert_eq "output path embeds self-assessment (barrier pattern)" "matched" "unmatched"
fi

# ---------------------------------------------------------------------------
# 3. read-gate blocks Verifier read of the output path (exit 2)
# ---------------------------------------------------------------------------

verifier_json="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"agent_type":"rnd-verifier"}' "$output_path")"
run_hook "$HOOK" "$verifier_json"
assert_exit_code "Verifier read of properties output is blocked (exit 2)" 2
assert_contains "Verifier read emits INFORMATION BARRIER" "INFORMATION BARRIER" "$HOOK_STDERR"

# ---------------------------------------------------------------------------
# 4. read-gate allows Builder read of the same path (exit 0)
# ---------------------------------------------------------------------------

builder_json="$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"},"agent_type":"rnd-builder"}' "$output_path")"
run_hook "$HOOK" "$builder_json"
assert_exit_code "Builder read of properties output is allowed (exit 0)" 0

# ---------------------------------------------------------------------------
# 5. Counter-example path: schema fixture missing a required field
# ---------------------------------------------------------------------------

bad_fixture="${tmp_project_dir}/bad-props.json"
printf '%s\n' '{"required":["name","value","missing_field"],"sample":{"name":"test","value":42}}' \
  > "$bad_fixture"

bad_output="${builds_dir}/T99-self-assessment-properties-fail.txt"
"$RUN_PROPS" schema "$bad_fixture" "$tmp_project_dir" > "$bad_output" 2>&1 || true

if [[ -f "$bad_output" ]]; then
  bad_content="$(cat "$bad_output")"
  assert_contains "failing schema fixture yields PROPERTY_COUNTER_EXAMPLE" \
    "PROPERTY_COUNTER_EXAMPLE" "$bad_content"
else
  assert_eq "failing schema fixture produces output file" "exists" "missing"
fi

report
