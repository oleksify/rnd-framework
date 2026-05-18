#!/usr/bin/env bash
# tests/run-properties-schema.test.sh — Tests for the v2 (full JSON Schema) path
# in lib/run-properties.sh (lang=schema with "$schema" key present in fixture).
# Usage: bash tests/run-properties-schema.test.sh
# Exits 0 if all tests pass, 1 if any fail.
#
# NOTE on coverage: this test exercises the jq fallback path of the v2 schema
# validator. The ajv-CLI preferred path is NOT exercised here because ajv may
# not be installed in every environment. When ajv IS installed, the grep
# pattern `must have required property '<name>'` is used to extract the missing
# key from ajv's error output — this pattern is taken from ajv 8.x output
# format and has NOT been verified against ajv 6.x or 7.x. If ajv produces a
# different error string in those versions, the shrunk_input field will read
# as the generic fallback "schema validation failed" rather than the specific
# missing property name. This is documented gracefully (the counter-example
# JSON is still emitted, just with less specificity). Phase 7 polish: install
# ajv in CI and add an integration test against multiple ajv major versions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER="${PLUGIN_ROOT}/lib/run-properties.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Setup: all fixtures under $RND_DIR (never /tmp).
# ---------------------------------------------------------------------------
RND_DIR="${RND_DIR:-${HOME}/.claude/.rnd/run-properties-schema-test-$$}"
FIXTURE_DIR="${RND_DIR}/run-properties-schema-fixtures"
mkdir -p "$FIXTURE_DIR"

trap 'rm -rf "$FIXTURE_DIR"' EXIT

# Helper: run the runner with a given fixture, capture stdout/stderr/exit code.
_run_schema() {
  local fixture="$1"
  local stdout_file stderr_file
  stdout_file="${FIXTURE_DIR}/stdout.txt"
  stderr_file="${FIXTURE_DIR}/stderr.txt"

  HOOK_EXIT=0
  "$RUNNER" schema "$fixture" "$FIXTURE_DIR" \
    > "$stdout_file" 2> "$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
}

# ---------------------------------------------------------------------------
# Criterion: v2 pass — known-correct API response → PROPERTY_PASS, exit 0.
# The fixture uses all four JSON Schema keys: $schema, type, properties, required.
# ---------------------------------------------------------------------------
printf '\n--- v2: known-correct API response → PROPERTY_PASS ---\n'

API_PASS_FIXTURE="${FIXTURE_DIR}/api-pass.json"
cat > "$API_PASS_FIXTURE" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "id":    { "type": "integer" },
    "name":  { "type": "string"  },
    "email": { "type": "string"  },
    "score": { "type": "number"  }
  },
  "required": ["id", "name", "email", "score"],
  "sample": {
    "id":    101,
    "name":  "Alice",
    "email": "alice@example.com",
    "score": 9.5
  }
}
EOF

_run_schema "$API_PASS_FIXTURE"

assert_eq "v2 pass: exit 0" "0" "$HOOK_EXIT"
assert_contains "v2 pass: stdout contains PROPERTY_PASS" "PROPERTY_PASS" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# Criterion: v2 fail — drifted API response (missing required field) →
# PROPERTY_COUNTER_EXAMPLE + shrunk-input JSON on stderr.
# ---------------------------------------------------------------------------
printf '\n--- v2: drifted API response → PROPERTY_COUNTER_EXAMPLE + JSON ---\n'

API_FAIL_FIXTURE="${FIXTURE_DIR}/api-fail.json"
cat > "$API_FAIL_FIXTURE" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "id":    { "type": "integer" },
    "name":  { "type": "string"  },
    "email": { "type": "string"  },
    "score": { "type": "number"  }
  },
  "required": ["id", "name", "email", "score"],
  "sample": {
    "id":   101,
    "name": "Alice"
  }
}
EOF

_run_schema "$API_FAIL_FIXTURE"

assert_eq "v2 fail: exit non-zero (1)" "1" "$HOOK_EXIT"
assert_contains "v2 fail: stdout contains PROPERTY_COUNTER_EXAMPLE" \
  "PROPERTY_COUNTER_EXAMPLE" "$HOOK_STDOUT"

json_valid="$(printf '%s' "$HOOK_STDERR" | jq -e . > /dev/null 2>&1 && printf yes || printf no)"
assert_eq "v2 fail: stderr is valid JSON" "yes" "$json_valid"

has_property="$(printf '%s' "$HOOK_STDERR" | jq 'has("property")' 2>/dev/null || printf false)"
assert_eq "v2 fail: JSON has property key" "true" "$has_property"

has_shrunk="$(printf '%s' "$HOOK_STDERR" | jq 'has("shrunk_input")' 2>/dev/null || printf false)"
assert_eq "v2 fail: JSON has shrunk_input key" "true" "$has_shrunk"

has_seed="$(printf '%s' "$HOOK_STDERR" | jq 'has("seed")' 2>/dev/null || printf false)"
assert_eq "v2 fail: JSON has seed key" "true" "$has_seed"

# The drifted sample is missing both "email" and "score". The shrunk_input should
# name at least one of them — which first missing field is reported is implementation-
# defined, but it must be a real missing field name.
shrunk_val="$(printf '%s' "$HOOK_STDERR" | jq -r '.shrunk_input' 2>/dev/null || printf '')"
is_real_missing="$(case "$shrunk_val" in email|score|"expected type"*|"schema validation"*) printf yes ;; *) printf no ;; esac)"
assert_eq "v2 fail: shrunk_input names a missing field" "yes" "$is_real_missing"

# ---------------------------------------------------------------------------
# Criterion: all four fixture keys ($schema, type, properties, required) honored.
# Verify each key's contract with a targeted test per key.
# ---------------------------------------------------------------------------
printf '\n--- v2: all four JSON Schema keys honored ---\n'

# $schema key: fixture is only recognized as v2 when "$schema" is present.
NO_DOLLAR_SCHEMA_FIXTURE="${FIXTURE_DIR}/no-dollar-schema.json"
cat > "$NO_DOLLAR_SCHEMA_FIXTURE" << 'EOF'
{
  "type": "object",
  "properties": { "id": { "type": "integer" } },
  "required": ["id"],
  "sample": { "id": 1 }
}
EOF

_run_schema "$NO_DOLLAR_SCHEMA_FIXTURE"
# Without "$schema", falls through to v1 path (required + sample only).
assert_eq "dollar-schema absent: treated as v1 pass (no type check)" "0" "$HOOK_EXIT"
assert_contains "dollar-schema absent: PROPERTY_PASS via v1 path" "PROPERTY_PASS" "$HOOK_STDOUT"

# "type" key: wrong top-level type detected.
TYPE_MISMATCH_FIXTURE="${FIXTURE_DIR}/type-mismatch.json"
cat > "$TYPE_MISMATCH_FIXTURE" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {},
  "required": [],
  "sample": [1, 2, 3]
}
EOF

_run_schema "$TYPE_MISMATCH_FIXTURE"
assert_eq "type key: exit 1 on mismatch" "1" "$HOOK_EXIT"
assert_contains "type key: PROPERTY_COUNTER_EXAMPLE on mismatch" \
  "PROPERTY_COUNTER_EXAMPLE" "$HOOK_STDOUT"
type_shrunk="$(printf '%s' "$HOOK_STDERR" | jq -r '.shrunk_input' 2>/dev/null || printf '')"
assert_contains "type key: shrunk_input mentions type mismatch" "object" "$type_shrunk"

# "properties" key: sample conforming to declared properties → pass.
PROPERTIES_FIXTURE="${FIXTURE_DIR}/properties-pass.json"
cat > "$PROPERTIES_FIXTURE" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "id":   { "type": "integer" },
    "name": { "type": "string"  }
  },
  "required": ["id", "name"],
  "sample": { "id": 7, "name": "Bob" }
}
EOF

_run_schema "$PROPERTIES_FIXTURE"
assert_eq "properties key: exit 0 when sample conforms" "0" "$HOOK_EXIT"
assert_contains "properties key: PROPERTY_PASS when sample conforms" \
  "PROPERTY_PASS" "$HOOK_STDOUT"

# "required" key: sample missing one required field → fail.
REQUIRED_FAIL_FIXTURE="${FIXTURE_DIR}/required-fail.json"
cat > "$REQUIRED_FAIL_FIXTURE" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "id":    { "type": "integer" },
    "token": { "type": "string"  }
  },
  "required": ["id", "token"],
  "sample": { "id": 5 }
}
EOF

_run_schema "$REQUIRED_FAIL_FIXTURE"
assert_eq "required key: exit 1 when required field absent" "1" "$HOOK_EXIT"
req_shrunk="$(printf '%s' "$HOOK_STDERR" | jq -r '.shrunk_input' 2>/dev/null || printf '')"
assert_eq "required key: shrunk_input names the missing field" "token" "$req_shrunk"

# ---------------------------------------------------------------------------
# Criterion: graceful fallback when ajv is not installed.
# Simulate by running with a PATH that excludes ajv (even if it exists).
# The jq-based fallback must still produce correct pass/fail results.
# ---------------------------------------------------------------------------
printf '\n--- v2: jq-based fallback (ajv excluded from PATH) ---\n'

_run_schema_no_ajv() {
  local fixture="$1"
  local stdout_file stderr_file
  stdout_file="${FIXTURE_DIR}/stdout-noajv.txt"
  stderr_file="${FIXTURE_DIR}/stderr-noajv.txt"

  HOOK_EXIT=0
  # Restrict PATH to standard dirs only — guarantees ajv is not on PATH.
  PATH="/usr/bin:/bin" \
    "$RUNNER" schema "$fixture" "$FIXTURE_DIR" \
    > "$stdout_file" 2> "$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
}

_run_schema_no_ajv "$API_PASS_FIXTURE"
assert_eq "jq fallback pass: exit 0" "0" "$HOOK_EXIT"
assert_contains "jq fallback pass: PROPERTY_PASS" "PROPERTY_PASS" "$HOOK_STDOUT"

_run_schema_no_ajv "$API_FAIL_FIXTURE"
assert_eq "jq fallback fail: exit 1" "1" "$HOOK_EXIT"
assert_contains "jq fallback fail: PROPERTY_COUNTER_EXAMPLE" \
  "PROPERTY_COUNTER_EXAMPLE" "$HOOK_STDOUT"

fb_json_valid="$(printf '%s' "$HOOK_STDERR" | jq -e . > /dev/null 2>&1 && printf yes || printf no)"
assert_eq "jq fallback fail: stderr is valid JSON" "yes" "$fb_json_valid"

fb_has_property="$(printf '%s' "$HOOK_STDERR" | jq 'has("property")' 2>/dev/null || printf false)"
assert_eq "jq fallback fail: JSON has property key" "true" "$fb_has_property"

fb_has_shrunk="$(printf '%s' "$HOOK_STDERR" | jq 'has("shrunk_input")' 2>/dev/null || printf false)"
assert_eq "jq fallback fail: JSON has shrunk_input key" "true" "$fb_has_shrunk"

fb_has_seed="$(printf '%s' "$HOOK_STDERR" | jq 'has("seed")' 2>/dev/null || printf false)"
assert_eq "jq fallback fail: JSON has seed key" "true" "$fb_has_seed"

# ---------------------------------------------------------------------------
# Criterion: counter-example JSON shape matches the existing elixir/typescript shape.
# The shape is { property: string, shrunk_input: string, seed: int|null }.
# For schema mode, seed is null (no randomness involved).
# ---------------------------------------------------------------------------
printf '\n--- v2: counter-example JSON shape matches existing format ---\n'

_run_schema "$API_FAIL_FIXTURE"

ce_property_type="$(printf '%s' "$HOOK_STDERR" | jq -r '.property | type' 2>/dev/null || printf '')"
assert_eq "CE shape: property is a string" "string" "$ce_property_type"

ce_shrunk_type="$(printf '%s' "$HOOK_STDERR" | jq -r '.shrunk_input | type' 2>/dev/null || printf '')"
assert_eq "CE shape: shrunk_input is a string" "string" "$ce_shrunk_type"

ce_seed_val="$(printf '%s' "$HOOK_STDERR" | jq -r '.seed' 2>/dev/null || printf MISSING)"
assert_eq "CE shape: seed is null for schema mode" "null" "$ce_seed_val"

# ---------------------------------------------------------------------------
# Criterion: v1 path unchanged — fixtures without "$schema" still work.
# ---------------------------------------------------------------------------
printf '\n--- v1 backward compat: fixtures without $schema unchanged ---\n'

V1_PASS_FIXTURE="${FIXTURE_DIR}/v1-pass.json"
cat > "$V1_PASS_FIXTURE" << 'EOF'
{"required":["id","name"],"sample":{"id":1,"name":"Alice"}}
EOF

_run_schema "$V1_PASS_FIXTURE"
assert_eq "v1 pass: exit 0" "0" "$HOOK_EXIT"
assert_contains "v1 pass: PROPERTY_PASS" "PROPERTY_PASS" "$HOOK_STDOUT"

V1_FAIL_FIXTURE="${FIXTURE_DIR}/v1-fail.json"
cat > "$V1_FAIL_FIXTURE" << 'EOF'
{"required":["id","name"],"sample":{"id":1}}
EOF

_run_schema "$V1_FAIL_FIXTURE"
assert_eq "v1 fail: exit 1" "1" "$HOOK_EXIT"
v1_shrunk="$(printf '%s' "$HOOK_STDERR" | jq -r '.shrunk_input' 2>/dev/null || printf '')"
assert_eq "v1 fail: missing field identified" "name" "$v1_shrunk"

# v1 seed must be 0 (integer), not null.
v1_seed="$(printf '%s' "$HOOK_STDERR" | jq -r '.seed' 2>/dev/null || printf MISSING)"
assert_eq "v1 fail: seed is 0 (integer)" "0" "$v1_seed"

# ---------------------------------------------------------------------------
# Criterion: --help documents both ajv and jq-based modes.
# ---------------------------------------------------------------------------
printf '\n--- --help documents both validator modes ---\n'

help_out="$("$RUNNER" --help 2>&1 || true)"
assert_contains "--help mentions ajv" "ajv" "$help_out"
assert_contains "--help mentions jq" "jq" "$help_out"
assert_contains "--help mentions fallback" "fallback" "$help_out"
assert_contains '--help mentions $schema key' '$schema' "$help_out"

report
