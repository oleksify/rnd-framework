#!/usr/bin/env bash
# Tests card-retrieve.sh tolerates a corpus mixing v1 (no specializes:) and
# v2 (with specializes:) cards. Runs against a fixture corpus and the live tree.
# Usage: RND_DIR=<session-dir> bash tests/card-retrieve-specializes.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/test-helpers.sh"

RETRIEVE="${PLUGIN_ROOT}/lib/card-retrieve.sh"

RND_DIR="${RND_DIR:-}"
if [[ -z "$RND_DIR" ]]; then
  printf 'RND_DIR must be set to the session artifact directory.\n' >&2
  exit 1
fi

FIXTURE_ROOT="${RND_DIR}/T2-fixture/cards"
if [[ ! -d "$FIXTURE_ROOT" ]]; then
  printf 'Fixture corpus not found at %s\n' "$FIXTURE_ROOT" >&2
  exit 1
fi

# Assert exit 0, empty stderr, and well-formed output lines for one invocation.
assert_retrieval_ok() {
  local desc="$1" role="$2" task_type="$3" cards_root="$4"
  local out stderr_file exit_code stderr_content bad_lines

  stderr_file="$(mktemp)"
  exit_code=0
  out="$(bash "$RETRIEVE" --role="$role" --task-type="$task_type" --max=10 \
    --cards-root="$cards_root" 2>"$stderr_file")" || exit_code=$?
  stderr_content="$(cat "$stderr_file")"
  rm -f "$stderr_file"

  assert_eq "${desc}: exit 0"      "0"  "$exit_code"
  assert_eq "${desc}: stderr empty" "" "$stderr_content"

  if [[ -n "$out" ]]; then
    bad_lines="$(printf '%s\n' "$out" | grep -v '/CARD-.*\.md$' || true)"
    assert_eq "${desc}: output lines match CARD-*.md" "" "$bad_lines"
  fi
}

# ---------------------------------------------------------------------------
# Fixture corpus: mixes v1 card (no specializes:) and v2 card (with specializes:)
# ---------------------------------------------------------------------------

printf '\n--- specializes: tolerance — fixture corpus ---\n'

assert_retrieval_ok "builder/new-feature" "builder"  "new-feature" "$FIXTURE_ROOT"
assert_retrieval_ok "verifier/refactor"   "verifier" "refactor"    "$FIXTURE_ROOT"
assert_retrieval_ok "cleanup/infra"       "cleanup"  "infra"       "$FIXTURE_ROOT"

builder_out="$(bash "$RETRIEVE" --role=builder --task-type=new-feature --max=10 \
  --cards-root="$FIXTURE_ROOT" 2>/dev/null)"
line_count="$(printf '%s\n' "$builder_out" | grep -c '.' || true)"
assert_eq "fixture: builder query returns ≥1 card" "1" "$(( line_count >= 1 ? 1 : 0 ))"

run1="$(bash "$RETRIEVE" --role=builder --task-type=new-feature --max=10 \
  --cards-root="$FIXTURE_ROOT" 2>/dev/null)"
run2="$(bash "$RETRIEVE" --role=builder --task-type=new-feature --max=10 \
  --cards-root="$FIXTURE_ROOT" 2>/dev/null)"
assert_eq "fixture: retrieval is deterministic" "$run1" "$run2"

# ---------------------------------------------------------------------------
# Live corpus regression guard
# ---------------------------------------------------------------------------

printf '\n--- specializes: tolerance — live cards/ tree ---\n'

LIVE_ROOT="${PLUGIN_ROOT}/cards"

assert_retrieval_ok "live builder/new-feature" "builder"  "new-feature" "$LIVE_ROOT"
assert_retrieval_ok "live verifier/refactor"   "verifier" "refactor"    "$LIVE_ROOT"
assert_retrieval_ok "live cleanup/infra"       "cleanup"  "infra"       "$LIVE_ROOT"

report
