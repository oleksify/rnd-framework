#!/usr/bin/env bash
# tests/lib-fp.test.sh — Tests for FP utility functions in hooks/lib.sh.
# Usage: bash tests/lib-fp.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

LIB="${SCRIPT_DIR}/../hooks/lib.sh"
# shellcheck source=../hooks/lib.sh
source "$LIB"

# ---------------------------------------------------------------------------
# jq_extract
# ---------------------------------------------------------------------------
printf '%s\n' '--- jq_extract ---'

# Extracts existing string field
result="$(jq_extract '{"tool_name":"Read","other":"val"}' '.tool_name')"
assert_eq "jq_extract: extracts existing string field" "Read" "$result"

# Extracts nested field
result="$(jq_extract '{"a":{"b":"nested"}}' '.a.b')"
assert_eq "jq_extract: extracts nested field" "nested" "$result"

# Returns empty string for missing field, exit 0
result="$(jq_extract '{"a":"b"}' '.missing')"
assert_eq "jq_extract: missing field returns empty string" "" "$result"

# Returns 0 for valid JSON (missing field)
jq_extract '{"a":"b"}' '.missing'
assert_eq "jq_extract: missing field returns exit 0" "0" "$?"

# Returns 0 for invalid JSON (fault-tolerant)
jq_extract 'not-json' '.field'
assert_eq "jq_extract: invalid JSON returns exit 0" "0" "$?"

# Returns empty string for invalid JSON
result="$(jq_extract 'not-json' '.field')"
assert_eq "jq_extract: invalid JSON returns empty string" "" "$result"

# ---------------------------------------------------------------------------
# guard_nonempty
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- guard_nonempty ---'

# Returns 0 (continue) when value is non-empty
guard_nonempty "hello" "should not print"
assert_eq "guard_nonempty: non-empty value returns 0" "0" "$?"

# Returns 1 when value is empty (caller uses || to early-exit)
_guard_empty_rc=0
guard_nonempty "" "value was empty" || _guard_empty_rc=$?
assert_eq "guard_nonempty: empty value returns 1" "1" "$_guard_empty_rc"

# Does not print anything to stdout when value is non-empty
stdout="$(guard_nonempty "val" "msg")"
assert_eq "guard_nonempty: no stdout when non-empty" "" "$stdout"

# Does not print to stdout when value is empty (message goes to stderr or is suppressed)
stdout="$(guard_nonempty "" "empty message" || true)"
assert_eq "guard_nonempty: no stdout when empty" "" "$stdout"

# ---------------------------------------------------------------------------
# strip_frontmatter
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- strip_frontmatter ---'

# Removes YAML frontmatter from content
input="---
name: foo
---
actual content"
result="$(printf '%s\n' "$input" | strip_frontmatter)"
assert_eq "strip_frontmatter: removes frontmatter block" "actual content" "$result"

# Removes frontmatter and leaves multi-line body
input2="---
key: val
another: thing
---
line one
line two"
result2="$(printf '%s\n' "$input2" | strip_frontmatter)"
assert_eq "strip_frontmatter: multi-line body preserved" "$(printf 'line one\nline two')" "$result2"

# Passes through content with no frontmatter delimiters
input3="no frontmatter here
just text"
result3="$(printf '%s\n' "$input3" | strip_frontmatter)"
assert_eq "strip_frontmatter: no delimiters passes through unchanged" "$(printf 'no frontmatter here\njust text')" "$result3"

# Empty input produces empty output
result4="$(printf '' | strip_frontmatter)"
assert_eq "strip_frontmatter: empty input produces empty output" "" "$result4"

# ---------------------------------------------------------------------------
# map_lines
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- map_lines ---'

# Helper function for tests
_upper() { printf '%s\n' "${1^^}"; }
_prefix() { printf '%s\n' ">> $1"; }

# Applies function to each line
result="$(printf 'hello\nworld\n' | map_lines _upper)"
assert_eq "map_lines: applies function to each line" "$(printf 'HELLO\nWORLD')" "$result"

# Works with a single line
result="$(printf 'one\n' | map_lines _prefix)"
assert_eq "map_lines: single line input" ">> one" "$result"

# Empty input produces empty output
result="$(printf '' | map_lines _upper)"
assert_eq "map_lines: empty input produces empty output" "" "$result"

# ---------------------------------------------------------------------------
# filter_lines
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- filter_lines ---'

# Helper: returns 0 (keep) if line contains letter 'a'
_has_a() { [[ "$1" == *a* ]]; }
# Helper: always returns 1 (drop everything)
_drop_all() { return 1; }

# Keeps only lines where function returns 0
result="$(printf 'apple\nbanana\ncherry\n' | filter_lines _has_a)"
assert_eq "filter_lines: keeps lines where function returns 0" "$(printf 'apple\nbanana')" "$result"

# Drops all lines when function always returns 1
result="$(printf 'foo\nbar\n' | filter_lines _drop_all)"
assert_eq "filter_lines: empty result when all lines dropped" "" "$result"

# Empty input produces empty output
result="$(printf '' | filter_lines _has_a)"
assert_eq "filter_lines: empty input produces empty output" "" "$result"

# ---------------------------------------------------------------------------
# reduce_lines
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- reduce_lines ---'

# Helper: concatenates accumulator and line
_concat() { printf '%s %s' "$1" "$2"; }
# Helper: sums integers
_sum() { printf '%d' $(( $1 + $2 )); }

# Accumulates via function from initial value
result="$(printf 'a\nb\nc\n' | reduce_lines _concat "")"
assert_eq "reduce_lines: concatenates lines with initial empty" " a b c" "$result"

# Sums numbers
result="$(printf '1\n2\n3\n' | reduce_lines _sum 0)"
assert_eq "reduce_lines: sums numbers" "6" "$result"

# Empty input returns initial value
result="$(printf '' | reduce_lines _concat "init")"
assert_eq "reduce_lines: empty input returns initial" "init" "$result"

# ---------------------------------------------------------------------------
# parse_input_stdout
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- parse_input_stdout ---'

# Parses valid JSON and prints 3 lines
valid_json='{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.txt"},"agent_type":"user"}'
output="$(printf '%s' "$valid_json" | parse_input_stdout)"
line1="$(printf '%s' "$output" | sed -n '1p')"
line2="$(printf '%s' "$output" | sed -n '2p')"
line3="$(printf '%s' "$output" | sed -n '3p')"
assert_eq "parse_input_stdout: line 1 is tool_name" "Write" "$line1"
assert_contains "parse_input_stdout: line 2 contains file_path" "file_path" "$line2"
assert_eq "parse_input_stdout: line 3 is agent_type" "user" "$line3"

# Returns 0 for valid JSON
printf '%s' "$valid_json" | parse_input_stdout > /dev/null
assert_eq "parse_input_stdout: returns 0 for valid JSON" "0" "$?"

# Malformed JSON: prints three empty lines, returns 0
bad_output="$(printf 'not-json' | parse_input_stdout)"
bad_line1="$(printf '%s' "$bad_output" | sed -n '1p')"
bad_line2="$(printf '%s' "$bad_output" | sed -n '2p')"
bad_line3="$(printf '%s' "$bad_output" | sed -n '3p')"
assert_eq "parse_input_stdout: malformed JSON line 1 is empty" "" "$bad_line1"
assert_eq "parse_input_stdout: malformed JSON line 2 is empty" "" "$bad_line2"
assert_eq "parse_input_stdout: malformed JSON line 3 is empty" "" "$bad_line3"

printf 'not-json' | parse_input_stdout > /dev/null
assert_eq "parse_input_stdout: returns 0 for malformed JSON" "0" "$?"

# ---------------------------------------------------------------------------
# parse_input backward compatibility
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- parse_input backward compat ---'

compat_json='{"tool_name":"Read","tool_input":{"file_path":"/foo/bar"},"agent_type":"assistant"}'
TOOL_NAME="" TOOL_INPUT="" AGENT_TYPE=""
parse_input <<< "$compat_json"
assert_eq "parse_input: sets TOOL_NAME" "Read" "$TOOL_NAME"
assert_contains "parse_input: sets TOOL_INPUT with file_path" "file_path" "$TOOL_INPUT"
assert_eq "parse_input: sets AGENT_TYPE" "assistant" "$AGENT_TYPE"

report
