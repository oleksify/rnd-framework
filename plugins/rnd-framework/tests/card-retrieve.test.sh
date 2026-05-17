#!/usr/bin/env bash
# tests/card-retrieve.test.sh — Tests for lib/card-retrieve.sh
# Usage: bash tests/card-retrieve.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

RETRIEVE="${PLUGIN_ROOT}/lib/card-retrieve.sh"

# ---------------------------------------------------------------------------
# Fixture: a minimal cards/ tree with known frontmatter under TMP_DIR
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CARDS_ROOT="${TMP_DIR}/cards"

# Builder cards — two with overlapping tags, one with no overlap
mkdir -p "${CARDS_ROOT}/builder/python"

cat > "${CARDS_ROOT}/builder/python/CARD-B1.md" <<'MD'
---
id: B1
role: builder
language: python
tags: [error-handling, defensive-programming]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
---
Content B1.
MD

cat > "${CARDS_ROOT}/builder/python/CARD-B2.md" <<'MD'
---
id: B2
role: builder
language: python
tags: [abstraction, premature-abstraction]
applicable_task_types: [new-feature, bugfix, refactor]
scope: medium
---
Content B2.
MD

cat > "${CARDS_ROOT}/builder/python/CARD-B3.md" <<'MD'
---
id: B3
role: builder
language: python
tags: [defensive-programming, validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
---
Content B3.
MD

# Verifier card — different role, should never appear in builder queries
mkdir -p "${CARDS_ROOT}/verifier/python"

cat > "${CARDS_ROOT}/verifier/python/CARD-V1.md" <<'MD'
---
id: V1
role: verifier
language: python
tags: [error-handling, critique-evidence]
applicable_task_types: [new-feature, bugfix, refactor]
scope: small
---
Content V1.
MD

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

printf '\n--- card-retrieve: --help ---\n'

out="$(bash "$RETRIEVE" --help 2>&1)"
exit_code=0
bash "$RETRIEVE" --help >/dev/null 2>&1 || exit_code=$?

assert_eq "--help exits 0" "0" "$exit_code"
assert_contains "--help lists --role"        "--role"        "$out"
assert_contains "--help lists --task-type"   "--task-type"   "$out"
assert_contains "--help lists --tags"        "--tags"        "$out"
assert_contains "--help lists --max"         "--max"         "$out"
assert_contains "--help lists --cards-root"  "--cards-root"  "$out"

printf '\n--- card-retrieve: positive retrieval ---\n'

# 3 builder cards exist; requesting 3 should return exactly 3 paths
out3="$(bash "$RETRIEVE" \
  --role=builder \
  --task-type=new-feature \
  --max=3 \
  --cards-root="${CARDS_ROOT}" 2>&1)"

line_count="$(printf '%s\n' "$out3" | grep -c . || true)"
assert_eq "3 cards returned for builder/new-feature/max=3" "3" "$line_count"

printf '\n--- card-retrieve: determinism ---\n'

run1="$(bash "$RETRIEVE" --role=builder --task-type=new-feature --max=3 --cards-root="${CARDS_ROOT}")"
run2="$(bash "$RETRIEVE" --role=builder --task-type=new-feature --max=3 --cards-root="${CARDS_ROOT}")"

assert_eq "two consecutive runs produce identical output" "$run1" "$run2"

printf '\n--- card-retrieve: negative (no cards for role) ---\n'

empty_out="$(bash "$RETRIEVE" --role=integrator --max=3 --cards-root="${CARDS_ROOT}" 2>&1)"
empty_exit=0
bash "$RETRIEVE" --role=integrator --max=3 --cards-root="${CARDS_ROOT}" >/dev/null 2>&1 || empty_exit=$?

assert_eq "unknown role exits 0"       "0"  "$empty_exit"
assert_eq "unknown role produces no output" ""  "$empty_out"

printf '\n--- card-retrieve: --max cap ---\n'

out2="$(bash "$RETRIEVE" --role=builder --max=2 --cards-root="${CARDS_ROOT}" 2>&1)"
line2="$(printf '%s\n' "$out2" | grep -c . || true)"

assert_eq "--max=2 returns at most 2 lines" "2" "$line2"

printf '\n--- card-retrieve: RND_CARDS_MAX_PER_SPAWN env override ---\n'

out_env="$(RND_CARDS_MAX_PER_SPAWN=1 bash "$RETRIEVE" --role=builder --cards-root="${CARDS_ROOT}" 2>&1)"
line_env="$(printf '%s\n' "$out_env" | grep -c . || true)"

assert_eq "RND_CARDS_MAX_PER_SPAWN=1 limits output to 1 line" "1" "$line_env"

printf '\n--- card-retrieve: scoring + tiebreaker order ---\n'

# Query with tag=error-handling: B1 should score higher (1 shared tag)
# B2 and B3 score 0 tags overlap; tiebreaker is id ASC → B2 before B3
out_scored="$(bash "$RETRIEVE" \
  --role=builder \
  --tags=error-handling \
  --max=3 \
  --cards-root="${CARDS_ROOT}")"

first_card="$(printf '%s\n' "$out_scored" | head -1 | xargs basename)"
assert_eq "highest-scoring card (error-handling match) is first" "CARD-B1.md" "$first_card"

# With max=3, B2 should come before B3 (id ASC tiebreaker at score=0)
second_card="$(printf '%s\n' "$out_scored" | head -2 | tail -1 | xargs basename)"
assert_eq "second card is B2 (id ASC tiebreaker)" "CARD-B2.md" "$second_card"

printf '\n--- card-retrieve: role filter isolates cards ---\n'

# Verifier card should never appear in builder results even if tags match
out_roles="$(bash "$RETRIEVE" \
  --role=builder \
  --tags=error-handling \
  --max=10 \
  --cards-root="${CARDS_ROOT}")"

if printf '%s\n' "$out_roles" | grep -q 'CARD-V1'; then
  assert_eq "verifier card does not appear in builder results" "no V1" "V1 found"
else
  assert_eq "verifier card does not appear in builder results" "no V1" "no V1"
fi

report
