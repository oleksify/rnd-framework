#!/usr/bin/env bash
set -euo pipefail

# run-properties.sh — Dispatch property execution to Elixir StreamData or
# TypeScript fast-check based on <lang>, with lazy runtime probing.
#
# Usage:
#   run-properties.sh <lang> <spec-or-sibling-path> <project-dir>
#   run-properties.sh --help
#
# Lang values: elixir, typescript
#
# Exit codes:
#   0  Properties passed (PROPERTY_PASS) or runtime absent (PROPERTY_SKIPPED).
#   1  Counter-example found (PROPERTY_COUNTER_EXAMPLE). Stderr: JSON object
#      with keys property, shrunk_input, seed.

_usage() {
  printf 'Usage: run-properties.sh <lang> <spec-or-sibling-path> <project-dir>\n\n'
  printf 'Lang values:\n'
  printf '  elixir      Invoke mix test --include property <path>\n'
  printf '  typescript  Invoke bun test <path>\n'
  printf '  schema      Check field presence in a JSON schema+sample fixture (v1: keys only).\n\n'
  printf 'Stdout status lines:\n'
  printf '  PROPERTY_PASS                          All properties passed.\n'
  printf '  PROPERTY_SKIPPED missing-runtime: <t>  Runtime <t> not on PATH.\n'
  printf '  PROPERTY_COUNTER_EXAMPLE               A counter-example was found.\n\n'
  printf 'On PROPERTY_COUNTER_EXAMPLE, stderr carries a JSON object:\n'
  printf '  { "property": "...", "shrunk_input": "...", "seed": <int> }\n'
  printf '  Caveat: for elixir, `seed` is the global ExUnit suite seed, not a\n'
  printf '  per-property seed — StreamData does not expose the latter in ExUnit\n'
  printf '  output. Pinned regression tests may need additional context to\n'
  printf '  deterministically reproduce the original failure.\n\n'
  printf 'Schema fixture format (lang=schema):\n'
  printf '  { "required": ["field1", "field2"], "sample": { ... } }\n'
  printf '  v1 checks key presence only; full JSON Schema semantics are a v2 concern.\n'
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
    # v1: presence-of-keys check only. Full JSON Schema semantics are a v2 concern.
    #
    # Schema fixture format (spec_path points at this JSON file):
    #   { "required": ["field1", "field2"], "sample": { ... } }
    #
    # Validate the fixture is parseable JSON BEFORE the presence check. Without
    # this guard, a malformed fixture would cause the jq call below to fail
    # silently — command-substitution assignment doesn't propagate $? under
    # `set -e` — and an empty `missing` would print PROPERTY_PASS, a false
    # positive that defeats the schema quality gate.
    if ! jq -e . "$spec_path" > /dev/null 2>&1; then
      printf 'run-properties.sh: schema fixture %s is not valid JSON\n' "$spec_path" >&2
      exit 2
    fi

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
    ;;

  *)
    printf 'run-properties.sh: unknown lang %q (expected elixir, typescript, or schema)\n' "$lang" >&2
    _usage >&2
    exit 1
    ;;

esac
