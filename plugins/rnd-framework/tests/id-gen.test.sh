#!/usr/bin/env bash
# tests/id-gen.test.sh — Tests for lib/id-gen.sh subcommand dispatch and slug behavior.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ID_GEN="${SCRIPT_DIR}/../lib/id-gen.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Helper: run id-gen.sh and capture stdout, stderr, exit code
# ---------------------------------------------------------------------------

run_id_gen() {
  local stdout_file stderr_file
  stdout_file="$(mktemp)"
  stderr_file="$(mktemp)"

  HOOK_EXIT=0
  "$ID_GEN" "$@" >"$stdout_file" 2>"$stderr_file" || HOOK_EXIT=$?

  HOOK_STDOUT="$(cat "$stdout_file")"
  HOOK_STDERR="$(cat "$stderr_file")"
  rm -f "$stdout_file" "$stderr_file"
}

# Helper: assert non-zero exit (any exit > 0 satisfies error contract)
assert_nonzero_exit() {
  local desc="$1"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$HOOK_EXIT" -ne 0 ]]; then
    printf '  PASS  %s\n' "$desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s (expected non-zero, got 0)\n' "$desc"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# Helper: assert string has length <= N
assert_len_le() {
  local desc="$1" max="$2" str="$3"
  local len="${#str}"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
  if [[ "$len" -le "$max" ]]; then
    printf '  PASS  %s (len=%d)\n' "$desc" "$len"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    printf '  FAIL  %s (len=%d > %d)\n' "$desc" "$len" "$max"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------
# executable bit
# ---------------------------------------------------------------------------
printf '%s\n' '--- id-gen.sh is executable ---'

TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ -x "$ID_GEN" ]]; then
  printf '  PASS  id-gen.sh is executable\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  id-gen.sh is not executable\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# ---------------------------------------------------------------------------
# slug: basic conversion
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- slug: basic conversion ---'

run_id_gen slug 'Some Task Title!'
assert_eq "slug of 'Some Task Title!'" "some-task-title" "$HOOK_STDOUT"

run_id_gen slug 'hello world'
assert_eq "slug of 'hello world'" "hello-world" "$HOOK_STDOUT"

run_id_gen slug 'ID Generator'
assert_eq "slug of 'ID Generator'" "id-generator" "$HOOK_STDOUT"

run_id_gen slug 'Emits protocol md'
assert_eq "slug of 'Emits protocol md'" "emits-protocol-md" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# slug: idempotence (≥3 distinct inputs)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- slug: idempotence ---'

for title in 'Some Task Title!' 'hello-world' 'ID Generator'; do
  first="$(bash "$ID_GEN" slug "$title")"
  second="$(bash "$ID_GEN" slug "$first")"
  assert_eq "idempotent: $title" "$first" "$second"
done

# ---------------------------------------------------------------------------
# slug: truncation at 32 chars for long input
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- slug: truncation to 32 chars ---'

long_input="$(printf 'a%.0s' {1..100})"
run_id_gen slug "$long_input"
assert_len_le "100-'a' slug length <= 32" 32 "$HOOK_STDOUT"

long_phrase="This is a very long title that exceeds thirty two characters by far and keeps going"
run_id_gen slug "$long_phrase"
assert_len_le "long-phrase slug length <= 32" 32 "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# slug: edge cases — leading/trailing special chars, repeated separators
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- slug: edge cases ---'

run_id_gen slug '  spaces around  '
assert_eq "slug strips leading/trailing spaces" "spaces-around" "$HOOK_STDOUT"

run_id_gen slug '---leading-dashes'
assert_eq "slug strips leading dashes" "leading-dashes" "$HOOK_STDOUT"

run_id_gen slug 'trailing-dashes---'
assert_eq "slug strips trailing dashes" "trailing-dashes" "$HOOK_STDOUT"

run_id_gen slug 'multiple   spaces'
assert_eq "slug collapses multiple spaces" "multiple-spaces" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# task subcommand
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- task subcommand ---'

run_id_gen task 1 3 'ID Generator'
assert_eq "task M1.T03.id-generator" "M1.T03.id-generator" "$HOOK_STDOUT"

run_id_gen task 2 10 'Deploy Pipeline'
assert_eq "task M2.T10.deploy-pipeline" "M2.T10.deploy-pipeline" "$HOOK_STDOUT"

run_id_gen task 1 1 'Some Task Title!'
assert_eq "task M1.T01.some-task-title" "M1.T01.some-task-title" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# assertion subcommand
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- assertion subcommand ---'

run_id_gen assertion 1 planner 'Emits protocol md'
assert_eq "assertion M1.planner.emits-protocol-md" "M1.planner.emits-protocol-md" "$HOOK_STDOUT"

run_id_gen assertion 2 builder 'Writes manifest file'
assert_eq "assertion M2.builder.writes-manifest-file" "M2.builder.writes-manifest-file" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
# error cases: invalid / missing args
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- error cases ---'

# unknown subcommand
run_id_gen bogus_subcommand 'arg'
assert_nonzero_exit "unknown subcommand exits non-zero"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ -n "$HOOK_STDERR" ]]; then
  printf '  PASS  unknown subcommand has non-empty stderr\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  unknown subcommand has empty stderr\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# task with non-numeric milestone
run_id_gen task abc 3 'title'
assert_nonzero_exit "task: non-numeric milestone exits non-zero"
TESTS_TOTAL=$((TESTS_TOTAL + 1))
if [[ -n "$HOOK_STDERR" ]]; then
  printf '  PASS  task non-numeric milestone has stderr message\n'
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  printf '  FAIL  task non-numeric milestone has empty stderr\n'
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# task with missing args
run_id_gen task 1
assert_nonzero_exit "task: missing args exits non-zero"

# assertion with missing args
run_id_gen assertion 1 planner
assert_nonzero_exit "assertion: missing args exits non-zero"

# slug with no args
run_id_gen slug
assert_nonzero_exit "slug: missing arg exits non-zero"

# ---------------------------------------------------------------------------
# hardening: rejection cases
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- hardening: rejection cases ---'

# purely-symbolic input produces empty slug
run_id_gen slug '!!!'
assert_exit_code "slug: purely-symbolic input exits 2" 2
assert_contains "slug: empty-slug error mentions empty or rejected" "empty" "$HOOK_STDERR"

# milestone=0 is rejected
run_id_gen task 0 1 'x'
assert_exit_code "task: milestone=0 exits 2" 2
assert_contains "task: zero-milestone error cites positive integer" "positive integer" "$HOOK_STDERR"

# non-numeric task_num is rejected
run_id_gen task 1 abc 'x'
assert_exit_code "task: non-numeric task_num exits 2" 2
assert_contains "task: non-numeric task_num error cites numeric" "numeric" "$HOOK_STDERR"

# area with dot is rejected; valid kebab area passes and emits correct ID
run_id_gen assertion 1 'evil.area' 'x'
assert_exit_code "assertion: dot in area exits 2" 2

run_id_gen assertion 1 'valid-area' 'x'
assert_exit_code "assertion: valid kebab area exits 0" 0
assert_eq "assertion: valid kebab area emits correct ID" "M1.valid-area.x" "$HOOK_STDOUT"

# ---------------------------------------------------------------------------
report
