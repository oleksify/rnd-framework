#!/usr/bin/env bash
# outside-view.sh — Query the DuckDB per-shape fail-rate view and render a
# calibrated reference-class block for the Planner spawn prompt.
#
# Usage:
#   outside-view.sh
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Outputs:
#   - Writes the rendered block to $RND_DIR/outside-view.md
#   - Emits the same block on stdout
#
# Exit codes:
#   0  Always (degrades gracefully when duckdb absent or corpus empty).
#   1  RND_DIR unset.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

N_THIN_CORPUS=5

# ---------------------------------------------------------------------------
# query_duckdb — run the per-shape fail-rate view from the .rnd root.
# Prints CSV rows to stdout; prints nothing on duckdb-absent or query error.
# ---------------------------------------------------------------------------
query_duckdb() {
  local rnd_root="$1"
  local sql_path="${SCRIPT_DIR}/stats/per_shape_fail_rate.sql"

  if ! command -v duckdb > /dev/null 2>&1; then
    return 0
  fi

  if [[ ! -f "$sql_path" ]]; then
    return 0
  fi

  (
    cd "$rnd_root"
    duckdb -csv -noheader \
      -c ".read '${sql_path}'" \
      -c "SELECT * FROM per_shape_fail_rate ORDER BY segment, shape" \
      2>/dev/null
  ) || true
}

# ---------------------------------------------------------------------------
# parse_rows — validate and normalise CSV rows from query_duckdb.
# Globals set after call:
#   PARSED_ROWS   — newline-separated valid rows
#   DROPPED_COUNT — count of malformed rows
#   N_TOTAL       — total verifier verdicts in the dogfood segment
# ---------------------------------------------------------------------------
parse_rows() {
  local csv_output="$1"

  PARSED_ROWS=""
  DROPPED_COUNT=0
  N_TOTAL=0

  if [[ -z "$csv_output" ]]; then
    return 0
  fi

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue

    IFS=',' read -ra fields <<< "$row"

    if [[ "${#fields[@]}" -ne 5 ]]; then
      DROPPED_COUNT=$((DROPPED_COUNT + 1))
      continue
    fi

    local segment="${fields[0]}"
    local shape="${fields[1]}"
    local task_count="${fields[2]}"
    local fail_count="${fields[3]}"
    local fail_rate="${fields[4]}"

    if [[ -z "$segment" || -z "$shape" || -z "$task_count" || -z "$fail_count" || -z "$fail_rate" ]]; then
      DROPPED_COUNT=$((DROPPED_COUNT + 1))
      continue
    fi

    # task_count feeds integer arithmetic below; a non-numeric value would
    # silently evaluate to 0 under $((...)). Drop the row like an empty field.
    if [[ ! "$task_count" =~ ^[0-9]+$ ]]; then
      DROPPED_COUNT=$((DROPPED_COUNT + 1))
      continue
    fi

    if [[ "$segment" == "dogfood" ]]; then
      N_TOTAL=$((N_TOTAL + task_count))
    fi

    if [[ -n "$PARSED_ROWS" ]]; then
      PARSED_ROWS="${PARSED_ROWS}"$'\n'"${segment},${shape},${task_count},${fail_count},${fail_rate}"
    else
      PARSED_ROWS="${segment},${shape},${task_count},${fail_count},${fail_rate}"
    fi

  done <<< "$csv_output"
}

# ---------------------------------------------------------------------------
# render_block — format the outside-view markdown block.
# Reads globals: PARSED_ROWS, DROPPED_COUNT, N_TOTAL, N_THIN_CORPUS.
# Prints the block to stdout.
# ---------------------------------------------------------------------------
render_block() {
  local duckdb_available="$1"

  printf '## Outside View (Reference Class)\n'
  printf '\n'
  printf '## Framing constraint\n'
  printf 'Shape base rate is a calibration anchor, NOT a license to pack more assertions\n'
  printf 'and NOT a trigger for theater-decomposition. If a shape'"'"'s historical FAIL rate\n'
  printf 'is low, that is evidence the rate is well-tracked for similar shapes — it is\n'
  printf 'NOT permission to compress decomposition. If a shape'"'"'s historical FAIL rate\n'
  printf 'is high, that is a warning to think carefully about decomposition — it is NOT\n'
  printf 'a mandate to shatter the task into micro-assertions.\n'
  printf '\n'

  if [[ "$duckdb_available" == "false" ]]; then
    printf '%s\n' "- n_total: 0"
    printf '%s\n' "- Mode: unavailable"

    if [[ "$DROPPED_COUNT" -gt 0 ]]; then
      printf '%s\n' "- dropped_rows: ${DROPPED_COUNT}"
    fi

    return 0
  fi

  printf '%s\n' "- n_total: ${N_TOTAL}"

  if [[ "$N_TOTAL" -lt "$N_THIN_CORPUS" ]]; then
    printf '%s\n' "- Mode: thin-corpus"

    if [[ "$DROPPED_COUNT" -gt 0 ]]; then
      printf '%s\n' "- dropped_rows: ${DROPPED_COUNT}"
    fi

    return 0
  fi

  printf '%s\n' "- Mode: ready"

  if [[ "$DROPPED_COUNT" -gt 0 ]]; then
    printf '%s\n' "- dropped_rows: ${DROPPED_COUNT}"
  fi

  if [[ -z "$PARSED_ROWS" ]]; then
    return 0
  fi

  printf '\n'

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue

    IFS=',' read -ra fields <<< "$row"

    local segment="${fields[0]}"
    local shape="${fields[1]}"
    local task_count="${fields[2]}"
    local fail_count="${fields[3]}"
    local fail_rate="${fields[4]}"

    printf '%s\n' "- Shape: ${shape}  segment=${segment}  task_count=${task_count}  fail_count=${fail_count}  fail_rate=${fail_rate}"

  done <<< "$PARSED_ROWS"
}

# ---------------------------------------------------------------------------
# main entrypoint
# ---------------------------------------------------------------------------

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'outside-view.sh: RND_DIR is not set\n' >&2
  exit 1
fi

# RND_ROOT may be overridden for testing (e.g. to point at a fixture corpus).
# In production it is derived from the project calibration path.
if [[ -n "${RND_ROOT:-}" ]]; then
  rnd_root="$RND_ROOT"
else
  calibration_path="$("${SCRIPT_DIR}/rnd-dir.sh" --calibration)"
  rnd_root="$(dirname "$(dirname "$calibration_path")")"
fi

duckdb_available="true"
if ! command -v duckdb > /dev/null 2>&1; then
  duckdb_available="false"
fi

csv_output=""
if [[ "$duckdb_available" == "true" ]]; then
  csv_output="$(query_duckdb "$rnd_root")"
fi

parse_rows "$csv_output"

block="$(render_block "$duckdb_available")"

printf '%s\n' "$block" | tee "${RND_DIR}/outside-view.md"
