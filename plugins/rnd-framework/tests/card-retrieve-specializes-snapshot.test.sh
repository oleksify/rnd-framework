#!/usr/bin/env bash
# tests/card-retrieve-specializes-snapshot.test.sh
# Snapshot test: a known builder/elixir/refactor query returns ≥2 paths,
# including the canon card that a specializing card references.
# Usage: bash tests/card-retrieve-specializes-snapshot.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

RETRIEVE="${PLUGIN_ROOT}/lib/card-retrieve.sh"
LIVE_CARDS_ROOT="${PLUGIN_ROOT}/cards"

# ---------------------------------------------------------------------------
# Fixture corpus: a minimal builder tree with one specializing card and its
# canon parent. The canon card does NOT match the query tags directly, so it
# can only appear in output via specializes: resolution.
# ---------------------------------------------------------------------------

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE_ROOT="${TMP_DIR}/cards"
mkdir -p "${FIXTURE_ROOT}/builder/generic"
mkdir -p "${FIXTURE_ROOT}/builder/elixir"

# Canon card: tags [invariants] — does NOT match query tag "validation"
cat > "${FIXTURE_ROOT}/builder/generic/CARD-P-IMPOSSIBLE-01.md" <<'CARD'
---
id: P-IMPOSSIBLE-01
role: builder
language: generic
tags: [invariants]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Use discriminated unions to make invalid states unrepresentable at the type level.
---
Canon body.
CARD

# Specializing card: tags [validation, boundaries] — matches query tag "validation"
cat > "${FIXTURE_ROOT}/builder/elixir/CARD-B9.md" <<'CARD'
---
id: B9
role: builder
language: elixir
tags: [validation, boundaries]
applicable_task_types: [new-feature, bugfix, refactor]
scope: Validate at the Ecto.Changeset boundary; keep business logic clean of raw-input checks.
specializes: [P-IMPOSSIBLE-01]
---
B9 body.
CARD

# Second card: no specializes, no matching tags
cat > "${FIXTURE_ROOT}/builder/elixir/CARD-B7.md" <<'CARD'
---
id: B7
role: builder
language: elixir
tags: [error-handling, control-flow]
applicable_task_types: [bugfix, refactor]
scope: Prefer with-chains over nested case; keep the happy path unindented.
---
B7 body.
CARD

# ---------------------------------------------------------------------------
# Fixture-based tests
# ---------------------------------------------------------------------------

printf '\n--- specializes snapshot: fixture corpus ---\n'

# Query: tags=validation, max=1 — only B9 scores; P-IMPOSSIBLE-01 must be
# appended via specializes: resolution. Total output should be ≥2 paths.
QUERY_OUT="$(bash "$RETRIEVE" \
  --role=builder \
  --task-type=refactor \
  --tags=validation \
  --max=1 \
  --cards-root="${FIXTURE_ROOT}" 2>/dev/null)"

LINE_COUNT="$(printf '%s\n' "$QUERY_OUT" | grep -c '.' || true)"
assert_eq "fixture: query returns ≥2 paths (scored card + canon parent)" \
  "1" "$(( LINE_COUNT >= 2 ? 1 : 0 ))"

assert_contains "fixture: output includes the specializing card" \
  "CARD-B9.md" "$QUERY_OUT"

assert_contains "fixture: output includes the canon parent card" \
  "CARD-P-IMPOSSIBLE-01.md" "$QUERY_OUT"

# Parents appear after the scored set: CARD-B9.md must come before CARD-P-IMPOSSIBLE-01.md
B9_LINE="$(printf '%s\n' "$QUERY_OUT" | grep -n 'CARD-B9.md' | cut -d: -f1)"
CANON_LINE="$(printf '%s\n' "$QUERY_OUT" | grep -n 'CARD-P-IMPOSSIBLE-01.md' | cut -d: -f1)"
assert_eq "fixture: specializing card appears before its canon parent" \
  "1" "$(( B9_LINE < CANON_LINE ? 1 : 0 ))"

# ---------------------------------------------------------------------------
# Deduplication: canon card already in scored set must appear only once.
# ---------------------------------------------------------------------------

printf '\n--- specializes snapshot: deduplication ---\n'

# Increase max=3 so P-IMPOSSIBLE-01 (which also has refactor task-type bonus)
# enters the scored set directly. With max=3, all 3 cards score. B9 also has
# specializes: [P-IMPOSSIBLE-01] — P-IMPOSSIBLE-01 must appear exactly once.
DEDUP_OUT="$(bash "$RETRIEVE" \
  --role=builder \
  --task-type=refactor \
  --tags=validation \
  --max=3 \
  --cards-root="${FIXTURE_ROOT}" 2>/dev/null)"

CANON_OCCURRENCES="$(printf '%s\n' "$DEDUP_OUT" | grep -c 'CARD-P-IMPOSSIBLE-01.md' || true)"
assert_eq "deduplication: canon card appears exactly once" \
  "1" "$CANON_OCCURRENCES"

# ---------------------------------------------------------------------------
# Determinism: two consecutive runs return identical output.
# ---------------------------------------------------------------------------

printf '\n--- specializes snapshot: determinism ---\n'

RUN1="$(bash "$RETRIEVE" --role=builder --task-type=refactor --tags=validation \
  --max=1 --cards-root="${FIXTURE_ROOT}" 2>/dev/null)"
RUN2="$(bash "$RETRIEVE" --role=builder --task-type=refactor --tags=validation \
  --max=1 --cards-root="${FIXTURE_ROOT}" 2>/dev/null)"
assert_eq "determinism: two consecutive runs produce identical output" "$RUN1" "$RUN2"

# ---------------------------------------------------------------------------
# No-specializes cards: v1 cards (no specializes: field) still work correctly.
# ---------------------------------------------------------------------------

printf '\n--- specializes snapshot: v1 card (no specializes) ---\n'

# B7 has no specializes: field. Query matching only B7.
V1_OUT="$(bash "$RETRIEVE" \
  --role=builder \
  --task-type=bugfix \
  --tags=error-handling \
  --max=1 \
  --cards-root="${FIXTURE_ROOT}" 2>/dev/null)"

V1_LINE_COUNT="$(printf '%s\n' "$V1_OUT" | grep -c '.' || true)"
assert_eq "v1 card: returns exactly 1 path (no parent appended)" "1" "$V1_LINE_COUNT"
assert_contains "v1 card: returns the matching card" "CARD-B7.md" "$V1_OUT"

# ---------------------------------------------------------------------------
# Live corpus: the known B9→P-IMPOSSIBLE-01 chain must be reachable.
# Query with tags=validation, task-type=refactor, max=1 — so canon card
# cannot enter via scoring; only via specializes: resolution.
# ---------------------------------------------------------------------------

printf '\n--- specializes snapshot: live corpus ---\n'

LIVE_OUT="$(bash "$RETRIEVE" \
  --role=builder \
  --task-type=refactor \
  --tags=validation \
  --max=1 \
  --cards-root="${LIVE_CARDS_ROOT}" 2>/dev/null)"

LIVE_LINE_COUNT="$(printf '%s\n' "$LIVE_OUT" | grep -c '.' || true)"
assert_eq "live: query returns ≥2 paths" \
  "1" "$(( LIVE_LINE_COUNT >= 2 ? 1 : 0 ))"

assert_contains "live: output includes canon card P-IMPOSSIBLE-01" \
  "CARD-P-IMPOSSIBLE-01.md" "$LIVE_OUT"

report
