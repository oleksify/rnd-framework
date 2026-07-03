#!/usr/bin/env bash
# remeasurement.sh — Re-measurement harness for dogfood corpus gating.
#
# The corpus boundary (the M5 ship moment) is a fixed epoch baked in below — NOT
# a commit SHA. A SHA needs a live git repo to resolve and is dropped by history
# rewrites; the boundary is conceptually a moment in time, so we store the time.
#
# Subcommands (boundary arg is optional; omit it for the M5 default):
#   corpus_count [boundary_epoch]   Print integer count of dogfood session dirs
#                                   whose timestamp is after the boundary epoch.
#   gate_met [boundary_epoch]       Exit 0 when corpus_count >= 10, else exit 1.
#   memo <output_path> [boundary]   Write a re-measurement memo to the given path.
#                                   Pending stub when gate unmet; full memo otherwise.
#
# The optional boundary arg accepts ONLY a positive epoch integer (used by tests);
# anything else (e.g. a commit SHA) is rejected loudly rather than silently
# degrading the count — see _resolve_boundary_epoch.
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

# M5 ship boundary. The post-M5 corpus is sessions created after M5 (v5.6.0)
# shipped. Stored as a fixed epoch, not a commit SHA: the boundary is a moment
# in time, and a SHA both needs a live git repo to resolve and is dropped by
# history rewrites. Source: v5.6.0 commit 62311e9, 2026-05-28T12:17:47+02:00.
readonly M5_EPOCH=1779963467

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

# Resolve the corpus-boundary epoch from an optional argument:
#   (empty)          -> the M5 default epoch
#   positive integer -> used verbatim (epoch override; used by tests)
#   anything else    -> FAIL LOUD (return 1, message on stderr). A measurement
#                       tool must never silently fall back and count everything,
#                       which is exactly what the old git/SHA path did when the
#                       SHA failed to resolve to an empty epoch.
_resolve_boundary_epoch() {
  local arg="${1:-}"

  if [[ -z "$arg" ]]; then
    printf '%s' "$M5_EPOCH"
    return 0
  fi

  if [[ "$arg" =~ ^[0-9]+$ ]] && [[ "$arg" -gt 0 ]]; then
    printf '%s' "$arg"
    return 0
  fi

  printf 'remeasurement: cannot resolve corpus boundary from %q — pass an empty argument for the M5 default or a positive epoch integer (a commit SHA is no longer accepted)\n' "$arg" >&2
  return 1
}

_parse_session_epoch() {
  local session_basename="$1"
  local ts_prefix="${session_basename:0:15}"  # "YYYYMMDD-HHMMSS"

  # BSD date (macOS): -j prevents setting the clock; -f parses the input format.
  date -j -f '%Y%m%d-%H%M%S' "$ts_prefix" '+%s' 2>/dev/null && return

  # GNU date (Linux): no -j flag; accepts free-form strings via -d.
  # Reformat YYYYMMDD-HHMMSS into "YYYY-MM-DD HH:MM:SS" using substring slices —
  # bash 3.2-safe, no external tools needed.
  local gnu_dt="${ts_prefix:0:4}-${ts_prefix:4:2}-${ts_prefix:6:2} ${ts_prefix:9:2}:${ts_prefix:11:2}:${ts_prefix:13:2}"
  date -d "$gnu_dt" '+%s' 2>/dev/null && return

  # Both branches failed — basename is malformed or date is unavailable.
  echo 0
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
  local slug_dir="$1" boundary_epoch="$2"
  local n=0
  local session_dir session_epoch sessions_root

  # Current layout: <slug>/branches/<branch>/sessions/<ts>/, with slash-containing
  # branch names preserved as nested directories under branches/.
  if [[ -d "${slug_dir}branches" ]]; then
    while IFS= read -r -d '' sessions_root; do
      for session_dir in "${sessions_root}/"*/; do
        [[ -d "$session_dir" ]] || continue
        session_epoch="$(_parse_session_epoch "$(basename "$session_dir")")"
        [[ "$session_epoch" -gt "$boundary_epoch" ]] && n=$((n + 1))
      done
    done < <(find "${slug_dir}branches" -type d -path '*/sessions' -print0 2>/dev/null)
  fi

  # Legacy layout: <slug>/sessions/<ts>/ (no branches/ tier)
  # The two glob roots are disjoint — no deduplication needed.
  for session_dir in "${slug_dir}sessions/"/*/; do
    [[ -d "$session_dir" ]] || continue
    session_epoch="$(_parse_session_epoch "$(basename "$session_dir")")"
    [[ "$session_epoch" -gt "$boundary_epoch" ]] && n=$((n + 1))
  done

  printf '%d' "$n"
}

# ---------------------------------------------------------------------------
# corpus_count [boundary_epoch]
# Prints the integer count of post-boundary dogfood session directories.
# Fails loud (return 1, no stdout) if the boundary arg cannot be resolved.
# Pure: reads filesystem; writes only to stdout.
# ---------------------------------------------------------------------------

corpus_count() {
  local boundary_epoch rnd_root count=0 slug_dir

  boundary_epoch="$(_resolve_boundary_epoch "${1:-}")" || return 1

  rnd_root="$(_resolve_config_dir)/.rnd"

  for slug_dir in "${rnd_root}/"/*/; do
    [[ -d "$slug_dir" ]] || continue
    _is_dogfood_slug "$(basename "$slug_dir")" || continue
    count=$((count + $(_count_sessions_in_slug "$slug_dir" "$boundary_epoch")))
  done

  printf '%d\n' "$count"
}

# ---------------------------------------------------------------------------
# gate_met [boundary_epoch]
# Exit 0 when corpus_count >= 10, exit 1 otherwise. Propagates a non-zero exit
# (without claiming a gate verdict) when the boundary cannot be resolved.
# Pure: delegates to corpus_count.
# ---------------------------------------------------------------------------

gate_met() {
  local n
  n="$(corpus_count "${1:-}")" || return 1

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
      -c ".read '${stats_dir}/${sql_file}'" \
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
  local today slugs
  today="$(date '+%Y-%m-%d')"
  slugs="${RND_DOGFOOD_SLUGS:-claude-130cb64f}"

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
Scope: framework dogfood corpus only — slug(s): ${slugs}. Re-measurement is a
framework self-measurement: it always reports on the framework's own development
sessions, independent of the project directory it was invoked from.

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
  local boundary="${2:-}"

  local n
  n="$(corpus_count "$boundary")" || return 1

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
