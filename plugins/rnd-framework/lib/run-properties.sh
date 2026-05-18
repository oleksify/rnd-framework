#!/usr/bin/env bash
set -euo pipefail

# run-properties.sh — Dispatch property execution to Elixir StreamData or
# TypeScript fast-check based on <lang>, with lazy runtime probing.
#
# Usage:
#   run-properties.sh <lang> <spec-or-sibling-path> <project-dir>
#   run-properties.sh --help
#
# Lang values: elixir, typescript, schema
#
# Exit codes:
#   0  Properties passed (PROPERTY_PASS) or runtime absent (PROPERTY_SKIPPED).
#   1  Counter-example found (PROPERTY_COUNTER_EXAMPLE). Stderr: JSON object
#      with keys property, shrunk_input, seed (seed is null for schema mode).

_usage() {
  printf 'Usage: run-properties.sh <lang> <spec-or-sibling-path> <project-dir>\n\n'
  printf 'Lang values:\n'
  printf '  elixir      Invoke mix test --include property <path>\n'
  printf '  typescript  Invoke bun test <path>\n'
  printf '  schema      Validate a JSON sample against a schema fixture.\n\n'
  printf 'Stdout status lines:\n'
  printf '  PROPERTY_PASS                          All properties passed.\n'
  printf '  PROPERTY_SKIPPED missing-runtime: <t>  Runtime <t> not on PATH.\n'
  printf '  PROPERTY_COUNTER_EXAMPLE               A counter-example was found.\n\n'
  printf 'On PROPERTY_COUNTER_EXAMPLE, stderr carries a JSON object:\n'
  printf '  { "property": "...", "shrunk_input": "...", "seed": <int|null> }\n'
  printf '  Caveat: for elixir, `seed` is the global ExUnit suite seed, not a\n'
  printf '  per-property seed — StreamData does not expose the latter in ExUnit\n'
  printf '  output. Pinned regression tests may need additional context to\n'
  printf '  deterministically reproduce the original failure.\n\n'
  printf 'Schema fixture format (lang=schema):\n'
  printf '  v1 (key-presence only) — fixture must contain "required" and "sample":\n'
  printf '    { "required": ["field1", "field2"], "sample": { ... } }\n'
  printf '  v2 (full JSON Schema) — detected when fixture contains a "$schema" key:\n'
  printf '    { "$schema": "...", "type": "object", "properties": {...}, "required": [...] }\n'
  printf '    Sample data must be passed as a separate file (second argument) or\n'
  printf '    embedded under a "sample" key alongside the full JSON Schema keys.\n'
  printf '  Validator selection (v2 only):\n'
  printf '    preferred: ajv CLI (command -v ajv) — full JSON Schema Draft-07 semantics.\n'
  printf '    fallback:  jq-based minimal check (type assertion + required-key presence).\n'
}

if [[ "${1:-}" == "--help" ]]; then
  _usage
  exit 0
fi

if [[ $# -lt 3 ]]; then
  printf 'run-properties.sh: expected <lang> <spec-path> <project-dir>, got %d args\n' "$#" >&2
  _usage >&2
  exit 1
fi

lang="$1"
spec_path="$2"
project_dir="$3"

# Parse StreamData / ExUnit failure output (single awk pass, POSIX awk).
# Outputs three lines: property=<v>, shrunk_input=<v>, seed=<v>
#
# Real StreamData 1.3.0 output uses:
#   "  1) property <name> (<Module>)" for the failing-block header
#   "* Clause:    var <- gen()" + "  Generated: <value>" for generated values
#   "Running ExUnit with seed: N" in the header for the suite seed
#
# Caveat: the seed reported here is the global ExUnit suite seed, not a
# per-property seed. StreamData does not expose the per-property seed in
# ExUnit failure output, so this is a best-effort surrogate — pinned
# regression tests that consume this seed may not deterministically
# reproduce the original counter-example without additional context.
_parse_elixir_failure() {
  awk '
    /^[[:space:]]+[0-9]+\)[[:space:]]+(property|test)[[:space:]]/ {
      line = $0
      sub(/.*\)[[:space:]]+(property|test)[[:space:]]+/, "", line)
      sub(/ \(.*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      prop = line
    }
    /\* Clause:/ { in_clause = 1 }
    in_clause && /[[:space:]]*Generated:/ {
      line = $0
      sub(/.*Generated:[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (shrunk == "") shrunk = line
      in_clause = 0
    }
    /[Ss]eed:/ {
      match($0, /[0-9]+/)
      seed = substr($0, RSTART, RLENGTH)
    }
    END {
      printf "property=%s\nshrunk_input=%s\nseed=%s\n", \
        (prop   != "" ? prop   : "unknown"), \
        (shrunk != "" ? shrunk : ""), \
        (seed   != "" ? seed   : "0")
    }
  '
}

# Parse fast-check failure output (single awk pass, POSIX awk).
# Outputs three lines: property=<v>, shrunk_input=<v>, seed=<v>
#
# Real bun 1.3.14 + fast-check 3.23.2 output uses:
#   "(fail) <name> [Nms]"  for failing test lines (no × character)
#   "Counterexample: [<value>]"  for the shrunk input
#   "{ seed: -N, path: ..., endOnFailure: true }"  for the config object
_parse_typescript_failure() {
  awk '
    /^[[:space:]]*\(fail\)[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*\(fail\)[[:space:]]+/, "", line)
      sub(/[[:space:]]+\[[0-9.]+ms\].*$/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line != "") prop = line
    }
    /Counterexample:/ {
      line = $0
      sub(/.*Counterexample:[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      shrunk = line
    }
    /seed:/ {
      match($0, /-?[0-9]+/)
      seed = substr($0, RSTART, RLENGTH)
    }
    END {
      printf "property=%s\nshrunk_input=%s\nseed=%s\n", \
        (prop   != "" ? prop   : "unknown"), \
        (shrunk != "" ? shrunk : ""), \
        (seed   != "" ? seed   : "0")
    }
  '
}

# Emit a counter-example JSON to stderr via jq -nc from parsed key=value lines.
# $1 = output file from the test runner
# $2 = parser function name (_parse_elixir_failure or _parse_typescript_failure)
_emit_counter_example_json() {
  local output_file="$1"
  local parser="$2"

  local prop shrunk seed
  while IFS='=' read -r key value; do
    case "$key" in
      property)     prop="$value"   ;;
      shrunk_input) shrunk="$value" ;;
      seed)         seed="$value"   ;;
    esac
  done < <("$parser" < "$output_file")

  jq -nc \
    --arg property    "${prop:-unknown}" \
    --arg shrunk_input "${shrunk:-}" \
    --argjson seed    "${seed:-0}" \
    '{property: $property, shrunk_input: $shrunk_input, seed: $seed}' \
    >&2
}

# ---------------------------------------------------------------------------
# Main dispatch — single case, no sub-scripts.
# ---------------------------------------------------------------------------

case "$lang" in

  elixir)
    if ! command -v mix > /dev/null 2>&1; then
      printf 'PROPERTY_SKIPPED missing-runtime: mix\n'
      exit 0
    fi

    tmp_out="$(mktemp)"
    trap 'rm -f "$tmp_out"' EXIT
    exit_code=0
    (cd "$project_dir" && mix test --include property "$spec_path") \
      > "$tmp_out" 2>&1 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
      printf 'PROPERTY_PASS\n'
      exit 0
    fi

    printf 'PROPERTY_COUNTER_EXAMPLE\n'
    _emit_counter_example_json "$tmp_out" _parse_elixir_failure
    exit 1
    ;;

  typescript)
    if ! command -v bun > /dev/null 2>&1; then
      printf 'PROPERTY_SKIPPED missing-runtime: bun\n'
      exit 0
    fi

    tmp_out="$(mktemp)"
    trap 'rm -f "$tmp_out"' EXIT
    exit_code=0
    (cd "$project_dir" && bun test "$spec_path") \
      > "$tmp_out" 2>&1 || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
      printf 'PROPERTY_PASS\n'
      exit 0
    fi

    printf 'PROPERTY_COUNTER_EXAMPLE\n'
    _emit_counter_example_json "$tmp_out" _parse_typescript_failure
    exit 1
    ;;

  schema)
    # Validate the fixture is parseable JSON before any further processing.
    # Without this guard, a malformed fixture would cause jq calls below to fail
    # silently — command-substitution assignment doesn't propagate $? under
    # `set -e` — and an empty result would print PROPERTY_PASS, a false positive.
    if ! jq -e . "$spec_path" > /dev/null 2>&1; then
      printf 'run-properties.sh: schema fixture %s is not valid JSON\n' "$spec_path" >&2
      exit 2
    fi

    # Detect v1 vs v2 by presence of the "$schema" key in the fixture.
    # v1: { "required": [...], "sample": { ... } }
    # v2: { "$schema": "...", "type": "object", "properties": {...}, "required": [...], "sample": {...} }
    has_dollar_schema="$(jq -r 'has("$schema") | tostring' "$spec_path")"

    if [[ "$has_dollar_schema" == "true" ]]; then
      # v2: full JSON Schema validation.
      #
      # The "sample" key carries the API response or data under test. It lives
      # alongside the JSON Schema keys inside the same fixture file.
      sample_data="$(jq '.sample' "$spec_path")"

      if [[ "$sample_data" == "null" || -z "$sample_data" ]]; then
        printf 'run-properties.sh: v2 schema fixture %s missing "sample" key\n' "$spec_path" >&2
        exit 2
      fi

      # Write sample to a temp file — used by both ajv and jq-fallback paths.
      tmp_data="$(mktemp)"
      trap 'rm -f "$tmp_data"' EXIT
      printf '%s\n' "$sample_data" > "$tmp_data"

      if command -v ajv > /dev/null 2>&1; then
        # ajv path: write a clean schema (without the "sample" key) and validate.
        tmp_schema="$(mktemp)"
        trap 'rm -f "$tmp_schema" "$tmp_data"' EXIT
        jq 'del(.sample)' "$spec_path" > "$tmp_schema"

        ajv_out="$(ajv validate -s "$tmp_schema" -d "$tmp_data" 2>&1)" && ajv_exit=0 || ajv_exit=$?

        if [[ $ajv_exit -eq 0 ]]; then
          printf 'PROPERTY_PASS\n'
          exit 0
        fi

        # Extract the failing field from ajv's error output.
        # ajv prints: "data must have required property 'fieldname'"
        failing_field="$(printf '%s\n' "$ajv_out" \
          | grep -o "must have required property '[^']*'" \
          | head -1 \
          | grep -o "'[^']*'" \
          | tr -d "'" || true)"

        if [[ -z "$failing_field" ]]; then
          failing_field="schema validation failed"
        fi

        printf 'PROPERTY_COUNTER_EXAMPLE\n'
        jq -nc \
          --arg property    "JSON Schema validation" \
          --arg shrunk_input "$failing_field" \
          '{property: $property, shrunk_input: $shrunk_input, seed: null}' \
          >&2
        exit 1

      else
        # jq fallback: minimal check — top-level type + required-key presence.
        #
        # Step 1: verify the sample's JSON type matches "type" (if declared).
        schema_type="$(jq -r '.type // empty' "$spec_path")"

        if [[ -n "$schema_type" ]]; then
          actual_type="$(jq -r 'type' "$tmp_data")"

          if [[ "$actual_type" != "$schema_type" ]]; then
            printf 'PROPERTY_COUNTER_EXAMPLE\n'
            jq -nc \
              --arg property    "JSON Schema type check" \
              --arg shrunk_input "expected type $schema_type, got $actual_type" \
              '{property: $property, shrunk_input: $shrunk_input, seed: null}' \
              >&2
            exit 1
          fi
        fi

        # Step 2: verify every required key is present in the sample.
        # Use --slurpfile to load the sample as a parsed JSON value (avoids
        # env-var string injection and handles nested structures correctly).
        missing="$(jq -r \
          --slurpfile data "$tmp_data" '
          (.required // []) as $req |
          $data[0] as $d |
          [ $req[] | . as $f | select(($d | has($f)) | not) ] |
          if length == 0 then "" else .[0] end
        ' "$spec_path")"

        if [[ -z "$missing" ]]; then
          printf 'PROPERTY_PASS\n'
          exit 0
        fi

        printf 'PROPERTY_COUNTER_EXAMPLE\n'
        jq -nc \
          --arg property    "JSON Schema required-key check" \
          --arg shrunk_input "$missing" \
          '{property: $property, shrunk_input: $shrunk_input, seed: null}' \
          >&2
        exit 1
      fi

    else
      # v1: presence-of-keys check only.
      #
      # Schema fixture format (spec_path points at this JSON file):
      #   { "required": ["field1", "field2"], "sample": { ... } }
      #
      # Single jq pass: collect required fields that are absent from the sample.
      # `. as $f` binds each field name before passing to has() — required because
      # has() interprets its argument as a key, not the current context.
      missing="$(jq -r '
        .required as $req |
        .sample as $data |
        [ $req[] | . as $f | select(($data | has($f)) | not) ] |
        if length == 0 then "" else .[0] end
      ' "$spec_path")"

      if [[ -z "$missing" ]]; then
        printf 'PROPERTY_PASS\n'
        exit 0
      fi

      printf 'PROPERTY_COUNTER_EXAMPLE\n'
      jq -nc \
        --arg property    "schema presence check" \
        --arg shrunk_input "$missing" \
        --argjson seed    0 \
        '{property: $property, shrunk_input: $shrunk_input, seed: $seed}' \
        >&2
      exit 1
    fi
    ;;

  *)
    printf 'run-properties.sh: unknown lang %q (expected elixir, typescript, or schema)\n' "$lang" >&2
    _usage >&2
    exit 1
    ;;

esac
