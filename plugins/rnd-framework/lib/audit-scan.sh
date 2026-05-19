#!/usr/bin/env bash
# audit-scan.sh — Query utilities for $RND_DIR/audit.jsonl.
#
# Usage:
#   audit-scan.sh revisions <task_id> <file_path>
#       Print the integer count of Write/Edit events in audit.jsonl
#       matching the given file_path. task_id is reserved for future
#       per-task attribution when audit records carry that field;
#       current Write/Edit records lack task_id so this counts
#       file-path matches across the full session.
#
#   audit-scan.sh verdict_history <task_id>
#       Print the space-separated verdict sequence for <task_id>
#       parsed from verifications/T<id>-verification*.md files,
#       ordered by file modification time (oldest first).
#       Prints FLIP_DETECTED instead when the sequence contains
#       PASS→FAIL→PASS or FAIL→PASS→FAIL.
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
  printf '  revisions <task_id> <file_path>   Print Write/Edit count for file_path in audit.jsonl\n'
  printf '  verdict_history <task_id>         Print verdict sequence; FLIP_DETECTED on flip\n'
  printf '  --help                            Print this usage and exit 0\n'
}

_require_rnd_dir() {
  if [[ -z "${RND_DIR:-}" ]]; then
    printf 'audit-scan.sh: RND_DIR is not set\n' >&2
    exit 1
  fi
}

_revisions() {
  local task_id="${1:?task_id required}"
  local file_path="${2:?file_path required}"

  _require_rnd_dir

  local audit="${RND_DIR}/audit.jsonl"

  if [[ ! -f "$audit" ]]; then
    printf '0\n'
    return 0
  fi

  # Count Write/Edit events matching file_path.
  # When a record has task_id, also require it matches.
  # When a record lacks task_id, match on file_path alone.
  local count
  count="$(jq -sc \
    --arg tid "$task_id" \
    --arg fp "$file_path" \
    '[.[] |
      select(.tool == "Write" or .tool == "Edit") |
      select(.file == $fp) |
      select(
        (.task_id == null or .task_id == "") or
        (.task_id == $tid)
      )
    ] | length' "$audit")"

  printf '%s\n' "$count"
}

_verdict_history() {
  local task_id="${1:?task_id required}"

  _require_rnd_dir

  local verif_dir="${RND_DIR}/verifications"

  if [[ ! -d "$verif_dir" ]]; then
    printf '\n'
    return 0
  fi

  # Collect all verification files for this task_id, sorted oldest-first.
  local verdicts=""

  if compgen -G "${verif_dir}/${task_id}-verification*.md" > /dev/null 2>&1; then
    local files
    # ls -t lists newest first; we want oldest-first so reverse with -r
    files="$(ls -tr "${verif_dir}/${task_id}-verification"*.md 2>/dev/null || true)"

    if [[ -z "$files" ]]; then
      printf '\n'
      return 0
    fi

    while IFS= read -r f; do
      local v
      v="$(grep -m1 '^## Overall Verdict:' "$f" 2>/dev/null | \
           grep -o 'PASS\|FAIL\|NEEDS_ITERATION\|PASS_QUALITY_NEEDS_ITERATION' | \
           head -n1 || true)"

      if [[ -n "$v" ]]; then
        if [[ -z "$verdicts" ]]; then
          verdicts="$v"
        else
          verdicts="$verdicts $v"
        fi
      fi
    done <<< "$files"
  fi

  if [[ -z "$verdicts" ]]; then
    printf '\n'
    return 0
  fi

  # Detect flip: PASS→FAIL→PASS or FAIL→PASS→FAIL
  # Convert to array by splitting on spaces
  local prev="" pprev="" flip=0
  local word
  for word in $verdicts; do
    if [[ -n "$pprev" && -n "$prev" ]]; then
      if [[ "$pprev" == "PASS" && "$prev" == "FAIL" && "$word" == "PASS" ]]; then
        flip=1
        break
      fi
      if [[ "$pprev" == "FAIL" && "$prev" == "PASS" && "$word" == "FAIL" ]]; then
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
    printf '%s\n' "$verdicts"
  fi
}

subcommand="${1:-}"

case "$subcommand" in
  --help)
    _usage
    ;;
  revisions)
    shift
    _revisions "$@"
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
