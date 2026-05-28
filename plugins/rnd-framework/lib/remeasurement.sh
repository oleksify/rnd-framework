#!/usr/bin/env bash
# remeasurement.sh — Re-measurement harness for dogfood corpus gating.
#
# Subcommands:
#   corpus_count <commit_sha>   Print integer count of dogfood session dirs
#                               whose timestamp is after the commit's epoch.
#   gate_met <commit_sha>       Exit 0 when corpus_count >= 10, exit 1 otherwise.
#   memo <output_path> <sha>    Write a re-measurement memo to the given path.
#                               Pending stub when gate unmet; full memo otherwise.
#
# Environment:
#   CLAUDE_CONFIG_DIR   Override resolved config dir (default: $HOME/.claude)
#   CLAUDE_PLUGIN_ROOT  Strips /plugins/cache/* suffix to derive config dir
#   RND_DOGFOOD_SLUGS   Comma-separated dogfood slug prefixes (default: claude-130cb64f)
set -euo pipefail

# ---------------------------------------------------------------------------
# M3 baseline constants
#
# At M3 close (session 20260527-181326-c1137013), the stat producers had fired
# for the first time on M3's own activity only (n=1 bootstrap). The per-shape
# FAIL rates, self-fail-vs-verdict gap, and iteration-depth distribution from
# the producer-fed views were uniformly absent — no historical data, only the
# M3 bootstrap session itself. These "pending — no data" figures are the M3
# baseline. Re-measurement must compare against this floor.
# ---------------------------------------------------------------------------

readonly M3_FAIL_RATE_NOTE="pending — no data (n=1 bootstrap session at M3 close; corpus too thin for non-zero rates)"
readonly M3_GAP_NOTE="pending — no data (same bootstrap constraint; gap view requires paired self-assessment + calibration records)"
readonly M3_ITER_NOTE="pending — no data (iteration-depth view requires calibration.jsonl records with verdict fields)"
readonly M3_SESSION="20260527-181326-c1137013"
readonly CORPUS_THRESHOLD=10

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_resolve_config_dir() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    local stripped="${CLAUDE_PLUGIN_ROOT%%/plugins/cache/*}"
    if [[ "$stripped" != "$CLAUDE_PLUGIN_ROOT" ]]; then
      printf '%s' "$stripped"
      return
    fi
  fi

  if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
    printf '%s' "$CLAUDE_CONFIG_DIR"
    return
  fi

  printf '%s' "$HOME/.claude"
}

_commit_epoch() {
  local sha="$1"
  git -C "${CLAUDE_PLUGIN_ROOT:-.}" show -s --format=%ct "$sha"
}

_parse_session_epoch() {
  local session_basename="$1"
  local ts_prefix="${session_basename:0:15}"  # "YYYYMMDD-HHMMSS"

  date -j -f '%Y%m%d-%H%M%S' "$ts_prefix" '+%s' 2>/dev/null || echo 0
}

_is_dogfood_slug() {
  local slug_basename="$1"
  local slugs="${RND_DOGFOOD_SLUGS:-claude-130cb64f}"

  local IFS=','
  local s
  for s in $slugs; do
    [[ "$slug_basename" = "$s" ]] && return 0
  done

  return 1
}

_count_sessions_in_slug() {
  local slug_dir="$1" commit_epoch="$2"
  local n=0
  local session_dir session_epoch

  for session_dir in "${slug_dir}branches/"/*/sessions/*/; do
    [[ -d "$session_dir" ]] || continue
    session_epoch="$(_parse_session_epoch "$(basename "$session_dir")")"
    [[ "$session_epoch" -gt "$commit_epoch" ]] && n=$((n + 1))
  done

  printf '%d' "$n"
}

# ---------------------------------------------------------------------------
# corpus_count <commit_sha>
# Prints the integer count of post-commit dogfood session directories.
# Pure: reads filesystem + git; writes only to stdout.
# ---------------------------------------------------------------------------

corpus_count() {
  local sha="$1"
  local commit_epoch rnd_root count=0 slug_dir

  commit_epoch="$(_commit_epoch "$sha")"
  rnd_root="$(_resolve_config_dir)/.rnd"

  for slug_dir in "${rnd_root}/"/*/; do
    [[ -d "$slug_dir" ]] || continue
    _is_dogfood_slug "$(basename "$slug_dir")" || continue
    count=$((count + $(_count_sessions_in_slug "$slug_dir" "$commit_epoch")))
  done

  printf '%d\n' "$count"
}

# ---------------------------------------------------------------------------
# gate_met <commit_sha>
# Exit 0 when corpus_count >= 10, exit 1 otherwise.
# Pure: delegates to corpus_count.
# ---------------------------------------------------------------------------

gate_met() {
  local sha="$1"
  local n
  n="$(corpus_count "$sha")"

  [[ "$n" -ge "$CORPUS_THRESHOLD" ]]
}

# ---------------------------------------------------------------------------
# _query_view <rnd_root> <stats_dir> <sql_file> <select_sql>
# Run a duckdb view query from the .rnd root. Prints pipe-delimited rows.
# Errors from duckdb are not suppressed — they propagate to stderr.
# ---------------------------------------------------------------------------

_query_view() {
  local rnd_root="$1" stats_dir="$2" sql_file="$3" select_sql="$4"

  (
    cd "$rnd_root"
    duckdb -noheader -list \
      -c ".read ${stats_dir}/${sql_file}" \
      -c "$select_sql"
  )
}

# ---------------------------------------------------------------------------
# render_memo <n> <fail_rate_rows> <gap_rows> <iter_rows>
# Pure transform: takes snapshot data as strings, returns a markdown memo.
#
# fail_rate_rows: newline-separated "segment|shape|task_count|fail_count|fail_rate"
# gap_rows:       newline-separated "segment|task_count|self_fail_count|verifier_fail_count|gap_count"
# iter_rows:      newline-separated "segment|iteration_count|task_count"
# ---------------------------------------------------------------------------

render_memo() {
  local n="$1"
  local fail_rate_rows="$2"
  local gap_rows="$3"
  local iter_rows="$4"
  local today
  today="$(date '+%Y-%m-%d')"

  # Build per-shape FAIL rate table (dogfood segment only)
  local fail_table=""
  if [[ -n "$fail_rate_rows" ]]; then
    local seg shape tc fc fr
    while IFS='|' read -r seg shape tc fc fr; do
      [[ "$seg" == "dogfood" ]] || continue
      fail_table="${fail_table}| ${shape} | ${tc} | ${fc} | ${fr} |\n"
    done <<< "$fail_rate_rows"
  fi

  if [[ -z "$fail_table" ]]; then
    fail_table="| (no dogfood data in corpus) | — | — | — |\n"
  fi

  # Build gap table (dogfood segment only)
  local gap_table=""
  if [[ -n "$gap_rows" ]]; then
    local seg tc sfc vfc gc
    while IFS='|' read -r seg tc sfc vfc gc; do
      [[ "$seg" == "dogfood" ]] || continue
      gap_table="| ${tc} | ${sfc} | ${vfc} | ${gc} |\n"
    done <<< "$gap_rows"
  fi

  if [[ -z "$gap_table" ]]; then
    gap_table="| (no dogfood data in corpus) | — | — | — |\n"
  fi

  # Build iteration depth table (dogfood segment only)
  local iter_table=""
  if [[ -n "$iter_rows" ]]; then
    local seg ic tc
    while IFS='|' read -r seg ic tc; do
      [[ "$seg" == "dogfood" ]] || continue
      iter_table="${iter_table}| ${ic} | ${tc} |\n"
    done <<< "$iter_rows"
  fi

  if [[ -z "$iter_table" ]]; then
    iter_table="| (no dogfood data in corpus) | — |\n"
  fi

  # Build delta table — only shapes present in M3 baseline; since M3 was
  # "no data", the delta table reports the current snapshot as the first
  # empirical reading (delta against the M3 floor of 0.0 for each shape).
  local delta_table=""
  if [[ -n "$fail_rate_rows" ]]; then
    local seg shape tc fc fr
    while IFS='|' read -r seg shape tc fc fr; do
      [[ "$seg" == "dogfood" ]] || continue
      # M3 baseline is 0.0 for all shapes (bootstrap floor); delta == current.
      delta_table="${delta_table}| ${shape} | 0.0000 (M3 floor) | ${fr} | ${fr} |\n"
    done <<< "$fail_rate_rows"
  fi

  if [[ -z "$delta_table" ]]; then
    delta_table="| (no shapes present in both M3 baseline and current snapshot) | — | — | — |\n"
  fi

  # Build follow-up signals section — flag shapes with non-zero fail_rate
  local followup_lines=""
  if [[ -n "$fail_rate_rows" ]]; then
    local seg shape tc fc fr
    while IFS='|' read -r seg shape tc fc fr; do
      [[ "$seg" == "dogfood" ]] || continue
      # Check if fail_rate is non-zero (any delta > 0 from M3 floor)
      if [[ "$fr" != "0.0" && "$fr" != "0.00" && "$fr" != "0.000" && "$fr" != "0.0000" && -n "$fr" ]]; then
        followup_lines="${followup_lines}- **${shape}**: fail_rate=${fr} (delta from M3 floor = ${fr})\n"
      fi
    done <<< "$fail_rate_rows"
  fi

  if [[ -z "$followup_lines" ]]; then
    followup_lines="No shapes with non-zero fail_rate in current snapshot — no follow-up signals flagged.\n"
  fi

  printf '%s' "# Re-measurement Memo

Date: ${today}
Corpus: N=${n} post-M5 dogfood sessions (threshold: ${CORPUS_THRESHOLD})

## M3 baseline recall

M3 session: \`${M3_SESSION}\`

**Per-shape FAIL rate baseline:** ${M3_FAIL_RATE_NOTE}

**Self-fail-vs-verdict gap baseline:** ${M3_GAP_NOTE}

**Iteration-depth baseline:** ${M3_ITER_NOTE}

The M3 baseline values are uniformly absent — the stat producers had fired for
the first time on M3's own activity (n=1 bootstrap). Zero rates are a floor,
not a signal: the first non-zero reading establishes the true empirical baseline.

## Current snapshot

### Per-shape FAIL rate (dogfood segment)

| shape | task_count | fail_count | fail_rate |
|---|---|---|---|
$(printf '%b' "$fail_table")

### Self-fail-vs-verdict gap (dogfood segment)

| task_count | self_fail_count | verifier_fail_count | gap_count |
|---|---|---|---|
$(printf '%b' "$gap_table")

### Iteration depth (dogfood segment)

| iteration_count | task_count |
|---|---|
$(printf '%b' "$iter_table")

## Delta vs M3

Only shapes present in both the M3 baseline and the current snapshot are included.
Since M3 was uniformly pending (no historical data), the M3 floor is 0.0000 for
every shape; the delta equals the current fail_rate.

| shape | M3 baseline | current | delta |
|---|---|---|---|
$(printf '%b' "$delta_table")

## M4+M5 confound

The post-M5 corpus reflects two simultaneous interventions that cannot be
disentangled without additional stratification:

- **M4 (outside-view injector, v5.5.0 at \`5738909\`):** adds a reference-class
  calibration block to the Planner prompt. Expected effect: uniform across shapes,
  because the outside-view block applies at the session level without shape
  discrimination.

- **M5 (hide-previous-plan re-plan flow, v5.6.0 at \`941cea0\`):** isolates the
  Planner from its prior plan during re-plans and introduces a structured
  replan diff. Expected effect: shape-heterogeneous — architecture and planning
  shapes should improve more than performance or edge-case shapes.

Any change observed since M3 is attributable to M4+M5 jointly, not to either
alone. Stratification by commit range (pre-M4, M4-only, M4+M5 cohorts) and by
effect signature (uniform improvement → M4; shape-heterogeneous → M5) are the
two available attribution approaches. Full stratification (by commit range and
effect signature) is documented in the remeasurement-memo command output.

## Follow-up signals

Shapes with |delta| > 10pp relative to M3 floor (0.0000) warrant investigation:

$(printf '%b' "$followup_lines")
"
}

# ---------------------------------------------------------------------------
# memo <output_path> <commit_sha>
# Write a re-measurement memo. When the corpus gate is unmet, writes a pending
# stub naming N and the threshold. When gate is met, queries duckdb and writes
# the full memo via render_memo.
# ---------------------------------------------------------------------------

memo() {
  local output_path="$1"
  local sha="$2"

  local n
  n="$(corpus_count "$sha")"

  if [[ "$n" -lt "$CORPUS_THRESHOLD" ]]; then
    printf 'pending — N=%d (threshold: %d; re-run once %d post-M5 sessions have accrued)\n' \
      "$n" "$CORPUS_THRESHOLD" "$CORPUS_THRESHOLD" > "$output_path"
    return 0
  fi

  # Gate met — query duckdb from the .rnd root
  local rnd_root
  rnd_root="$(_resolve_config_dir)/.rnd"

  # Locate stats SQL files via CLAUDE_PLUGIN_ROOT if available, else relative to this script
  local stats_dir
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    stats_dir="${CLAUDE_PLUGIN_ROOT}/lib/stats"
  else
    stats_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/stats"
  fi

  # Guard: the calibration views hard-error when no calibration.jsonl files exist.
  # Use duckdb's glob() table function (returns empty rows, never errors) to probe first.
  local has_calib
  has_calib="$(cd "$rnd_root" && duckdb -noheader -list -c "SELECT count(*) FROM glob('*/calibration.jsonl')" 2>/dev/null || echo 0)"

  local fail_rate_rows="" gap_rows="" iter_rows=""
  if [[ "${has_calib:-0}" -gt 0 ]]; then
    fail_rate_rows="$(_query_view "$rnd_root" "$stats_dir" "per_shape_fail_rate.sql" \
      "SELECT segment, shape, task_count, fail_count, fail_rate FROM per_shape_fail_rate WHERE segment='dogfood' ORDER BY shape")"

    gap_rows="$(_query_view "$rnd_root" "$stats_dir" "self_fail_vs_verdict_gap.sql" \
      "SELECT segment, task_count, self_fail_count, verifier_fail_count, gap_count FROM self_fail_vs_verdict_gap WHERE segment='dogfood'")"

    iter_rows="$(_query_view "$rnd_root" "$stats_dir" "iteration_depth.sql" \
      "SELECT segment, iteration_count, task_count FROM iteration_depth WHERE segment='dogfood' ORDER BY iteration_count")"
  fi

  render_memo "$n" "$fail_rate_rows" "$gap_rows" "$iter_rows" > "$output_path"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

subcommand="${1:-}"
shift || true

case "$subcommand" in
  corpus_count) corpus_count "$@" ;;
  gate_met)     gate_met "$@" ;;
  memo)         memo "$@" ;;
  *)
    printf 'Usage: %s {corpus_count|gate_met|memo} <args>\n' "$(basename "$0")" >&2
    exit 1
    ;;
esac
