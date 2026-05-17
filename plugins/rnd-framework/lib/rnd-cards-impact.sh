#!/usr/bin/env bash
# rnd-cards-impact.sh — Compare iterations-to-PASS distributions pre/post a rollout date,
# broken down per task_type. Reads calibration.jsonl and prints a markdown table.
#
# Usage:
#   rnd-cards-impact.sh --since=<ISO-date> [--per-type-min=<N>]
#
# Arguments:
#   --since=<ISO date>    Required. Split date: records before this date are "pre",
#                         records on or after are "post". Format: YYYY-MM-DD or full ISO 8601.
#   --per-type-min=<N>    Optional. Minimum sample size on each side to emit a verdict.
#                         Default: 3. Buckets below this on either side emit "insufficient-data".
#
# Output: markdown table with columns:
#   task_type | pre-N | pre-median | pre-p75 | post-N | post-median | post-p75 | verdict
#
# Verdict logic (based on median delta of 0.5):
#   improved          — post_median < pre_median - 0.5
#   regressed         — post_median > pre_median + 0.5
#   no-change         — otherwise (medians within 0.5 of each other)
#   insufficient-data — either pre-N or post-N < --per-type-min
#
# Iterations-to-PASS for a task: count of NEEDS_ITERATION records for that taskId before
# the first PASS verdict within the same task scope. Tasks with no PASS verdict are excluded.
# The task is assigned to the pre or post bucket based on the timestamp of its first record
# (i.e., when the task started, not when it finished).
#
# Records with no task_type field default to "infra" (per orchestration policy).
# Records with no timestamp field are excluded from the analysis.
#
# Environment:
#   CLAUDE_PLUGIN_DATA   Preferred calibration.jsonl location (falls back to rnd-dir.sh).
#   CLAUDE_PLUGIN_ROOT   Required for rnd-dir.sh fallback path resolution.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_usage() {
  printf 'Usage: rnd-cards-impact.sh --since=<ISO-date> [--per-type-min=<N>]\n\n'
  printf 'Arguments:\n'
  printf '  --since=<ISO-date>    Required. Split date between pre-rollout and post-rollout.\n'
  printf '  --per-type-min=<N>    Minimum sample size per side for a verdict (default: 3).\n'
  printf '\nOutput: markdown table with columns:\n'
  printf '  task_type | pre-N | pre-median | pre-p75 | post-N | post-median | post-p75 | verdict\n'
  printf '\nVerdict thresholds (median delta of 0.5):\n'
  printf '  improved          — post_median < pre_median - 0.5\n'
  printf '  regressed         — post_median > pre_median + 0.5\n'
  printf '  no-change         — otherwise\n'
  printf '  insufficient-data — either side has fewer than --per-type-min samples\n'
}

_calib_file() {
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    printf '%s/calibration.jsonl' "$CLAUDE_PLUGIN_DATA"
  else
    "${_SCRIPT_DIR}/rnd-dir.sh" --calibration
  fi
}

since=""
per_type_min=3

for arg in "$@"; do
  case "$arg" in
    --since=*)
      since="${arg#--since=}"
      ;;
    --per-type-min=*)
      per_type_min="${arg#--per-type-min=}"
      ;;
    --help|-h)
      _usage
      exit 0
      ;;
    *)
      printf 'rnd-cards-impact.sh: unknown argument: %s\n' "$arg" >&2
      _usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$since" ]]; then
  printf 'rnd-cards-impact.sh: --since is required\n' >&2
  _usage >&2
  exit 1
fi

calib="$(_calib_file)"

if [[ ! -f "$calib" ]]; then
  printf 'rnd-cards-impact.sh: calibration file not found: %s\n' "$calib" >&2
  exit 1
fi

# All task_type values to report on, in deterministic display order.
TASK_TYPES=(refactor new-feature bugfix docs config infra)

# ---------------------------------------------------------------------------
# Core jq program.
#
# Input: the calibration.jsonl file is passed as a positional argument;
# we use [inputs] (with -n flag) to read all lines.
#
# Algorithm:
# 1. Load all records that have a timestamp. Default task_type to "infra".
# 2. Group by taskId. Within each group, sort by timestamp.
# 3. Find the first PASS record. Exclude tasks with no PASS.
# 4. Count NEEDS_ITERATION records whose timestamp is strictly before the first PASS.
# 5. Mark each task with its start_ts (timestamp of first record in group) and task_type.
# 6. For each task_type: partition tasks into pre (start_ts < since) and post (>= since).
# 7. Compute N, median (floor((N-1)/2) index), p75 (floor(0.75*(N-1)) index) for each side.
# 8. Emit one JSON object per task_type.
# ---------------------------------------------------------------------------

jq_program='
# Sort array and pick element at given fraction of (length-1).
def pct_idx(arr; frac):
  arr | sort as $s
  | ($s | length) as $n
  | if $n == 0 then null
    else $s[(($n - 1) * frac) | floor]
    end;

[inputs
  | select(.timestamp != null)
  | .task_type //= "infra"]
| group_by(.taskId)
| map(
    sort_by(.timestamp) as $sorted
    | ($sorted | map(select(.verdict == "PASS")) | first) as $first_pass
    | select($first_pass != null)
    | {
        task_type: ($first_pass.task_type // "infra"),
        start_ts:  $sorted[0].timestamp,
        iterations: (
          $sorted
          | map(select(.timestamp < $first_pass.timestamp
                        and .verdict == "NEEDS_ITERATION"))
          | length
        )
      }
  )
| . as $tasks
| $arg_types
| split(",")
| map(. as $tt |
    ($tasks | map(select(.task_type == $tt)))    as $bucket
    | ($bucket | map(select(.start_ts <  $arg_since))) as $pre
    | ($bucket | map(select(.start_ts >= $arg_since))) as $post
    | ($pre  | map(.iterations)) as $pc
    | ($post | map(.iterations)) as $qc
    | ($pc | length) as $pn
    | ($qc | length) as $qn
    | {
        task_type:   $tt,
        pre_n:       $pn,
        pre_median:  (pct_idx($pc; 0.5)  // "—"),
        pre_p75:     (pct_idx($pc; 0.75) // "—"),
        post_n:      $qn,
        post_median: (pct_idx($qc; 0.5)  // "—"),
        post_p75:    (pct_idx($qc; 0.75) // "—"),
        verdict:     (
          if $pn < $arg_min or $qn < $arg_min
          then "insufficient-data"
          elif (pct_idx($qc; 0.5) // 0) < ((pct_idx($pc; 0.5) // 0) - 0.5)
          then "improved"
          elif (pct_idx($qc; 0.5) // 0) > ((pct_idx($pc; 0.5) // 0) + 0.5)
          then "regressed"
          else "no-change"
          end
        )
      }
  )
'

types_arg="$(IFS=','; printf '%s' "${TASK_TYPES[*]}")"

rows="$(jq -rn \
  --arg  arg_since "$since" \
  --argjson arg_min "$per_type_min" \
  --arg  arg_types "$types_arg" \
  "$jq_program" \
  "$calib")"

# Print markdown table.
printf '| task_type    | pre-N | pre-median | pre-p75 | post-N | post-median | post-p75 | verdict           |\n'
printf '|--------------|-------|------------|---------|--------|-------------|----------|-------------------|\n'

while IFS= read -r row; do
  tt="$(      printf '%s' "$row" | jq -r '.task_type')"
  pre_n="$(   printf '%s' "$row" | jq -r '.pre_n')"
  pre_med="$( printf '%s' "$row" | jq -r '.pre_median')"
  pre_p75="$( printf '%s' "$row" | jq -r '.pre_p75')"
  post_n="$(  printf '%s' "$row" | jq -r '.post_n')"
  post_med="$(printf '%s' "$row" | jq -r '.post_median')"
  post_p75="$(printf '%s' "$row" | jq -r '.post_p75')"
  verd="$(    printf '%s' "$row" | jq -r '.verdict')"

  printf '| %-12s | %5s | %10s | %7s | %6s | %11s | %8s | %-17s |\n' \
    "$tt" "$pre_n" "$pre_med" "$pre_p75" "$post_n" "$post_med" "$post_p75" "$verd"
done < <(printf '%s' "$rows" | jq -c '.[]')
