#!/usr/bin/env bash
# Tests for lib/outside-view.sh
# Usage: bash tests/outside-view-query.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/../lib/outside-view.sh"
FIXTURE_ROOT="${SCRIPT_DIR}/../lib/stats/fixtures"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

make_session_dir() {
  local name="$1"
  local dir="${TMP_DIR}/${name}"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

make_rnd_root() {
  local name="$1"
  local dir="${TMP_DIR}/rnd-${name}"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

make_duckdb_shim() {
  local shim_dir="$1"
  local output="$2"
  mkdir -p "$shim_dir"
  printf '#!/usr/bin/env bash\nprintf '"'"'%s\n'"'"' %q\n' "$output" > "${shim_dir}/duckdb"
  chmod +x "${shim_dir}/duckdb"
}

# ---------------------------------------------------------------------------
# Test group: script exists and is executable
# ---------------------------------------------------------------------------
printf '%s\n' '--- outside-view-query: script exists and is executable ---'

assert_eq "script file exists" "0" "$(test -f "$SCRIPT" && echo 0 || echo 1)"
assert_eq "script is executable" "0" "$(test -x "$SCRIPT" && echo 0 || echo 1)"
assert_eq "script is non-empty" "0" "$(test -s "$SCRIPT" && echo 0 || echo 1)"

# ---------------------------------------------------------------------------
# Test group: renders block from fixture corpus
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-query: renders fixture block ---'

session_dir="$(make_session_dir "fixture-session")"
stdout="$(RND_DIR="$session_dir" RND_ROOT="$FIXTURE_ROOT" RND_DOGFOOD_SLUGS="claude-130cb64f" "$SCRIPT")"

header_match="$(printf '%s\n' "$stdout" | grep -cE '^## Outside View \(Reference Class\)$' || true)"
assert_eq "header line present" "1" "$header_match"

mode_match="$(printf '%s\n' "$stdout" | grep -cE '^- Mode:' || true)"
assert_eq "Mode line present" "1" "$mode_match"

ntotal_match="$(printf '%s\n' "$stdout" | grep -cE '^- n_total:' || true)"
assert_eq "n_total line present" "1" "$ntotal_match"

shape_match="$(printf '%s\n' "$stdout" | grep -cE '^- Shape:' || true)"
assert_eq "at least one Shape line present" "1" "$([ "$shape_match" -ge 1 ] && echo 1 || echo 0)"

framing_match="$(printf '%s\n' "$stdout" | grep -cE 'calibration anchor' || true)"
assert_eq "framing constraint present" "1" "$framing_match"

file_nonempty="$(test -s "${session_dir}/outside-view.md" && echo 0 || echo 1)"
assert_eq "outside-view.md written and non-empty" "0" "$file_nonempty"

# ---------------------------------------------------------------------------
# Test group: duckdb absent — degrades to Mode: unavailable
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-query: duckdb absent degrades gracefully ---'

session_no_duck="$(make_session_dir "no-duckdb-session")"
rnd_no_duck="$(make_rnd_root "no-duckdb")"

exit_code=0
stdout_no_duck="$(RND_DIR="$session_no_duck" RND_ROOT="$rnd_no_duck" PATH="/usr/bin:/bin" "$SCRIPT")" || exit_code=$?

assert_eq "duckdb-absent exits 0" "0" "$exit_code"

unavail_match="$(printf '%s\n' "$stdout_no_duck" | grep -cE 'Mode: unavailable' || true)"
assert_eq "Mode: unavailable present" "1" "$unavail_match"

no_fail_rate="$(printf '%s\n' "$stdout_no_duck" | grep -cE 'fail_rate=[0-9]' || true)"
assert_eq "no fail_rate rows when unavailable" "0" "$no_fail_rate"

# ---------------------------------------------------------------------------
# Test group: empty corpus — degrades to Mode: thin-corpus, n_total: 0
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-query: empty corpus degrades to thin-corpus ---'

session_empty="$(make_session_dir "empty-session")"
rnd_empty="$(make_rnd_root "empty")"

exit_code=0
stdout_empty="$(RND_DIR="$session_empty" RND_ROOT="$rnd_empty" "$SCRIPT")" || exit_code=$?

assert_eq "empty corpus exits 0" "0" "$exit_code"

thin_match="$(printf '%s\n' "$stdout_empty" | grep -cE 'Mode: thin-corpus' || true)"
assert_eq "Mode: thin-corpus on empty corpus" "1" "$thin_match"

ntotal_zero="$(printf '%s\n' "$stdout_empty" | grep -cE 'n_total: 0$' || true)"
assert_eq "n_total: 0 on empty corpus" "1" "$ntotal_zero"

no_shape_rate="$(printf '%s\n' "$stdout_empty" | grep -cE 'fail_rate=[0-9]' || true)"
assert_eq "no fail_rate rows when thin-corpus" "0" "$no_shape_rate"

# ---------------------------------------------------------------------------
# Test group: thin-corpus gate — 4-verdict corpus triggers thin-corpus mode
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-query: thin-corpus gate (4 verdicts) ---'

session_thin="$(make_session_dir "thin-session")"
rnd_thin="$(make_rnd_root "thin")"
slug_thin="${rnd_thin}/claude-130cb64f"
mkdir -p "${slug_thin}/sessions/s1"

printf '%s\n' \
  '{"taskId":"M1.T-a.x","sessionId":"s1","verdict":"PASS","timestamp":"2026-05-01T10:00:00Z"}' \
  '{"taskId":"M1.T-b.x","sessionId":"s1","verdict":"PASS","timestamp":"2026-05-01T10:01:00Z"}' \
  '{"taskId":"M1.T-c.x","sessionId":"s1","verdict":"FAIL","timestamp":"2026-05-01T10:02:00Z"}' \
  '{"taskId":"M1.T-d.x","sessionId":"s1","verdict":"PASS","timestamp":"2026-05-01T10:03:00Z"}' \
  > "${slug_thin}/calibration.jsonl"

printf '%s\n' \
  '{"session_id":"s1","assertion_id":"a1","shape":"wiring","confidence":"high","task_id":"M1.T-a.x","timestamp":"2026-05-01T09:00:00Z"}' \
  '{"session_id":"s1","assertion_id":"a2","shape":"wiring","confidence":"high","task_id":"M1.T-b.x","timestamp":"2026-05-01T09:01:00Z"}' \
  '{"session_id":"s1","assertion_id":"a3","shape":"crud","confidence":"high","task_id":"M1.T-c.x","timestamp":"2026-05-01T09:02:00Z"}' \
  '{"session_id":"s1","assertion_id":"a4","shape":"crud","confidence":"high","task_id":"M1.T-d.x","timestamp":"2026-05-01T09:03:00Z"}' \
  > "${slug_thin}/sessions/s1/audit.jsonl"

exit_code=0
stdout_thin="$(RND_DIR="$session_thin" RND_ROOT="$rnd_thin" "$SCRIPT")" || exit_code=$?

assert_eq "4-verdict corpus exits 0" "0" "$exit_code"

thin_mode_match="$(printf '%s\n' "$stdout_thin" | grep -cE 'Mode: thin-corpus' || true)"
assert_eq "4-verdict corpus: Mode: thin-corpus" "1" "$thin_mode_match"

no_bare_rate="$(printf '%s\n' "$stdout_thin" | grep -cE 'fail_rate=[0-9]+\.[0-9]+' || true)"
assert_eq "4-verdict corpus: no bare fail_rate values" "0" "$no_bare_rate"

n_thin_count="$(grep -c '^N_THIN_CORPUS=5$' "$SCRIPT")"
assert_eq "N_THIN_CORPUS=5 defined exactly once in script" "1" "$n_thin_count"

# ---------------------------------------------------------------------------
# Test group: row validation — malformed row dropped, valid row rendered
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-query: row validation with duckdb shim ---'

session_shim="$(make_session_dir "shim-session")"
rnd_shim="$(make_rnd_root "shim")"
shim_bin="${TMP_DIR}/shim-bin"
mkdir -p "$shim_bin"

cat > "${shim_bin}/duckdb" << 'SHIM'
#!/usr/bin/env bash
printf 'dogfood,wiring,5,1,0.2\n'
printf 'dogfood,crud\n'
SHIM
chmod +x "${shim_bin}/duckdb"

exit_code=0
stdout_shim="$(RND_DIR="$session_shim" RND_ROOT="$rnd_shim" PATH="${shim_bin}:${PATH}" "$SCRIPT")" || exit_code=$?

assert_eq "shim exits 0" "0" "$exit_code"

dropped_match="$(printf '%s\n' "$stdout_shim" | grep -cE 'dropped_rows: 1' || true)"
assert_eq "dropped_rows: 1 in block" "1" "$dropped_match"

wiring_match="$(printf '%s\n' "$stdout_shim" | grep -cE 'Shape: wiring' || true)"
assert_eq "valid row (wiring) appears in block" "1" "$wiring_match"

crud_match="$(printf '%s\n' "$stdout_shim" | grep -cE 'Shape: crud' || true)"
assert_eq "malformed row (crud) not in Shape listing" "0" "$crud_match"

# ---------------------------------------------------------------------------
# Test group: per_shape_fail_rate keeps session/task shape joins scoped
# even when task ids repeat across sessions
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-query: per_shape_fail_rate joins on session_id + task_id ---'

rnd_join_root="$(make_rnd_root "shape-join")"
slug_join="${rnd_join_root}/join-slug"
mkdir -p "${slug_join}/branches/main/sessions/s1" "${slug_join}/branches/main/sessions/s2"

printf '%s\n' \
  '{"task_id":"M1.T01.same-task","session_id":"s1","verdict":"PASS","timestamp":"2026-05-01T10:00:00Z"}' \
  '{"task_id":"M1.T01.same-task","session_id":"s2","verdict":"NEEDS_ITERATION","timestamp":"2026-05-01T10:01:00Z"}' \
  > "${slug_join}/calibration.jsonl"

printf '%s\n' \
  '{"event":"assertion_shape","task_id":"M1.T01.same-task","session_id":"s1","shape":"wiring","timestamp":"2026-05-01T09:00:00Z"}' \
  > "${slug_join}/branches/main/sessions/s1/audit.jsonl"

printf '%s\n' \
  '{"event":"assertion_shape","task_id":"M1.T01.same-task","session_id":"s2","shape":"data","timestamp":"2026-05-01T09:01:00Z"}' \
  > "${slug_join}/branches/main/sessions/s2/audit.jsonl"

join_query_output="$(
  cd "$rnd_join_root"
  duckdb -csv \
    -c ".read ${SCRIPT_DIR}/../lib/stats/per_shape_fail_rate.sql" \
    -c "SELECT segment, shape, task_count, fail_count, fail_rate FROM per_shape_fail_rate ORDER BY shape;"
)"

assert_contains "shape-join: data row keeps only session s2 verdict" "feature,data,1,1,1.0" "$join_query_output"
assert_contains "shape-join: wiring row keeps only session s1 verdict" "feature,wiring,1,0,0.0" "$join_query_output"

cross_count="$(printf '%s\n' "$join_query_output" | grep -c '^feature,.*,2,' || true)"
assert_eq "shape-join: no shape row cross-counts both sessions" "0" "$cross_count"

# ---------------------------------------------------------------------------
# Test group: backfill preserves snake_case session_id with camelCase fallback
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- outside-view-query: backfill preserves snake_case session_id ---'

rnd_backfill_root="$(make_rnd_root "backfill")"
slug_backfill="${rnd_backfill_root}/backfill-slug"
mkdir -p "$slug_backfill"

printf '%s\n' \
  '{"task_id":"M1.T01.current-shape","session_id":"snake-session","verdict":"PASS","iterationCount":0,"criticality":"HIGH","timestamp":"2026-05-01T10:00:00Z"}' \
  '{"taskId":"M1.T02.legacy-shape","sessionId":"camel-session","verdict":"FAIL","iterationCount":1,"criticality":"LOW","timestamp":"2026-05-01T10:01:00Z"}' \
  > "${slug_backfill}/calibration.jsonl"

backfill_query_output="$(
  cd "$rnd_backfill_root"
  duckdb -csv \
    -c ".read ${SCRIPT_DIR}/../lib/stats/backfill.sql" \
    -c "SELECT task_id, session_id FROM backfill ORDER BY task_id;"
)"

assert_contains "backfill: snake_case session_id preserved" "M1.T01.current-shape,snake-session" "$backfill_query_output"
assert_contains "backfill: camelCase sessionId still supported" "M1.T02.legacy-shape,camel-session" "$backfill_query_output"

null_session_count="$(printf '%s\n' "$backfill_query_output" | grep -c ',$' || true)"
assert_eq "backfill: no projected row has null session_id" "0" "$null_session_count"

# ---------------------------------------------------------------------------
report
