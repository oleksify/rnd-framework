#!/usr/bin/env bash
# audit-scan.sh — Query utilities for $RND_DIR/verifications/.
#
# Usage:
#   audit-scan.sh verdict_history <task_id>
#       Print the space-separated verdict sequence for <task_id>
#       parsed from verifications/T<id>-verification*.md files,
#       ordered by file modification time (oldest first).
#       Prints FLIP_DETECTED instead when the sequence contains
#       PASS→non-pass→PASS or non-pass→PASS→non-pass, where non-pass
#       includes FAIL, NEEDS_ITERATION, and PASS_QUALITY_NEEDS_ITERATION.
#
#   audit-scan.sh --help
#       Print this usage and exit 0.
#
# Environment:
#   RND_DIR  Path to the active RND session directory (required).
#
# Exit codes:
#   0  Success.
#   1  Missing argument, bad subcommand, or RND_DIR unset.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_usage() {
  printf 'Usage: audit-scan.sh <subcommand> [args]\n\n'
  printf 'Subcommands:\n'
  printf '  verdict_history <task_id>   Print verdict sequence; FLIP_DETECTED on flip\n'
  printf '  --help                      Print this usage and exit 0\n'
}

_require_rnd_dir() {
  if [[ -z "${RND_DIR:-}" ]]; then
    printf 'audit-scan.sh: RND_DIR is not set\n' >&2
    exit 1
  fi
}

_sorted_verification_files() {
  local task_id="${1:?task_id required}"
  local verif_dir="${2:?verif_dir required}"
  local files=()
  local file

  shopt -s nullglob
  files=( "${verif_dir}/${task_id}-verification"*.md )
  shopt -u nullglob

  if [[ "${#files[@]}" -eq 0 ]]; then
    return 0
  fi

  for file in "${files[@]}"; do
    local mtime
    mtime="$(stat -f '%m' "$file" 2>/dev/null || stat -c '%Y' "$file" 2>/dev/null)"
    printf '%s\t%s\n' "$mtime" "$file"
  done | sort -n -k1,1 -k2,2 | while IFS=$'\t' read -r _mtime file; do
    printf '%s\n' "$file"
  done
}

_extract_overall_verdict() {
  local report_file="${1:?report_file required}"
  local verdict_line=""
  local verdict=""

  verdict_line="$(grep -m1 '^## Overall Verdict:' "$report_file" 2>/dev/null || true)"
  if [[ -z "$verdict_line" ]]; then
    return 0
  fi

  verdict_line="${verdict_line#'## Overall Verdict:'}"
  verdict_line="${verdict_line#"${verdict_line%%[![:space:]]*}"}"
  verdict="${verdict_line%%[[:space:]]*}"

  printf '%s' "$verdict"
}

_is_pass_verdict() {
  local verdict="${1:-}"
  [[ "$verdict" == "PASS" ]]
}

_is_iteration_verdict() {
  local verdict="${1:-}"

  case "$verdict" in
    FAIL|NEEDS_ITERATION|PASS_QUALITY_NEEDS_ITERATION)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

_verdict_history() {
  local task_id="${1:?task_id required}"

  _require_rnd_dir

  local verif_dir="${RND_DIR}/verifications"

  if [[ ! -d "$verif_dir" ]]; then
    printf '\n'
    return 0
  fi

  local verdicts=()
  local report_file
  local verdict

  while IFS= read -r report_file; do
    verdict="$(_extract_overall_verdict "$report_file")"
    if [[ -n "$verdict" ]]; then
      verdicts+=( "$verdict" )
    fi
  done < <(_sorted_verification_files "$task_id" "$verif_dir")

  if [[ "${#verdicts[@]}" -eq 0 ]]; then
    printf '\n'
    return 0
  fi

  local prev="" pprev="" flip=0
  local word
  for word in "${verdicts[@]}"; do
    if [[ -n "$pprev" && -n "$prev" ]]; then
      if _is_pass_verdict "$pprev" && _is_iteration_verdict "$prev" && _is_pass_verdict "$word"; then
        flip=1
        break
      fi
      if _is_iteration_verdict "$pprev" && _is_pass_verdict "$prev" && _is_iteration_verdict "$word"; then
        flip=1
        break
      fi
    fi
    pprev="$prev"
    prev="$word"
  done

  if [[ "$flip" -eq 1 ]]; then
    printf 'FLIP_DETECTED\n'
  else
    local joined_verdicts
    joined_verdicts="$(IFS=' '; printf '%s' "${verdicts[*]}")"
    printf '%s\n' "$joined_verdicts"
  fi
}

subcommand="${1:-}"

case "$subcommand" in
  --help)
    _usage
    ;;
  verdict_history)
    shift
    _verdict_history "$@"
    ;;
  *)
    _usage >&2
    exit 1
    ;;
esac
