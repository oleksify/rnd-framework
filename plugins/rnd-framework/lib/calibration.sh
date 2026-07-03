#!/usr/bin/env bash
# calibration.sh — Helpers for the calibration auto-escalation loop.
#
# Usage:
#   calibration.sh window <tier> [N=10]
#       Print last N calibration.jsonl records filtered by criticality == <tier>.
#       Records with or without assertion_id are both included.
#
#   calibration.sh false_pass_rate <tier> [N=10]
#       Print the fraction of records in the window whose false_verdict_flag (or
#       legacy falseVerdictFlag) is FALSE_PASS or FALSE_PASS_PROXY, formatted as
#       a 2-decimal string (e.g. 0.30).
#
#   calibration.sh should_promote <tier> [N=10]
#       Exit 0 iff false_pass_rate >= 0.20 AND RND_DISABLE_AUTO_ESCALATION != "1".
#       Exit non-zero otherwise.
#
#   calibration.sh promote_tier <tier>
#       Print the promoted tier: LOW->NORMAL, NORMAL->HIGH, HIGH->HIGH.
#       Exit non-zero for unknown tiers.
#
#   calibration.sh task_type_window <type> [N=10]
#       Print last N calibration.jsonl records filtered by task_type == <type>.
#       task_type values: refactor | new-feature | bugfix | docs | config | infra
#
#   calibration.sh assertion_id_window <assertion_id> [N=10]
#       Print last N calibration.jsonl records that carry assertion_id == <assertion_id>.
#       Historical records without assertion_id are excluded from this view.
#
#   calibration.sh consecutive_clean <shape>
#       Print the trailing consecutive-clean (session,shape) run count for <shape>,
#       computed live from the slug-root post-review.jsonl. Per-finding rows are
#       collapsed to ONE clean/dirty verdict per (session,shape) BEFORE counting;
#       a session with any finding is one dirty run that resets the streak to 0.
#       Prints 0 (exit 0) when post-review.jsonl is absent.
#
#   calibration.sh validity <shape>
#       Exit 0 and print "expert" iff <shape> has >= 5 consecutive clean runs
#       (mirroring outside-view.sh's N_THIN_CORPUS=5). Otherwise print
#       "novice <count>" and exit non-zero. Recomputed from post-review.jsonl on
#       every call — no persisted streak state — so an appended dirty row resets
#       the streak at the next invocation (one-strike demotion).
#
#   calibration.sh --help
#       Print this usage and exit 0.
#
# Environment:
#   RND_DISABLE_AUTO_ESCALATION  Set to "1" to make should_promote always exit non-zero.
#   CLAUDE_PLUGIN_DATA           Preferred calibration.jsonl location (falls back to rnd-dir.sh).
#   CLAUDE_PLUGIN_ROOT           Required for rnd-dir.sh fallback path resolution.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_calib_file() {
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    printf '%s/calibration.jsonl' "$CLAUDE_PLUGIN_DATA"
  else
    "${_SCRIPT_DIR}/rnd-dir.sh" --calibration
  fi
}

# Expert threshold: a shape becomes expert at 5 consecutive clean runs.
# Mirrors outside-view.sh's N_THIN_CORPUS=5 — the same reference-class
# floor below which a per-shape signal is too thin to trust.
N_EXPERT_CONSECUTIVE_CLEAN=5

# post-review.jsonl lives at the slug root, sibling to calibration.jsonl.
_postreview_file() {
  printf '%s/post-review.jsonl' "$(dirname "$(_calib_file)")"
}

_usage() {
  printf 'Usage: calibration.sh <subcommand> [args]\n\n'
  printf 'Subcommands:\n'
  printf '  window <tier> [N=10]                          Print last N records for <tier> (LOW|NORMAL|HIGH)\n'
  printf '  false_pass_rate <tier> [N=10]                 Print false-PASS rate (0.00-1.00) for <tier>\n'
  printf '  should_promote <tier> [N=10]                  Exit 0 if rate >= 0.20 and escalation not disabled\n'
  printf '  promote_tier <tier>                           Print promoted tier (LOW->NORMAL, NORMAL->HIGH, HIGH->HIGH)\n'
  printf '  task_type_window <type> [N=10]                Print last N records filtered by task_type\n'
  printf '  assertion_id_window <assertion_id> [N=10]     Print last N records with assertion_id == <assertion_id>\n'
  printf '  consecutive_clean <shape>                     Print trailing consecutive-clean run count for <shape>\n'
  printf '  validity <shape>                              Exit 0 + "expert" if >= 5 consecutive clean, else "novice <n>"\n'
}

_window() {
  local tier="${1:?tier required}"
  local n="${2:-10}"
  local calib
  calib="$(_calib_file)"

  if [[ ! -f "$calib" ]]; then
    printf '' ; return 0
  fi

  jq -c --arg tier "$tier" 'select(.criticality == $tier)' "$calib" | tail -n "$n"
}

_false_pass_rate() {
  local tier="${1:?tier required}"
  local n="${2:-10}"
  local records total count

  records="$(_window "$tier" "$n")"

  if [[ -z "$records" ]]; then
    printf '0.00\n'
    return 0
  fi

  total="$(printf '%s\n' "$records" | jq -sc 'length')"
  count="$(printf '%s\n' "$records" \
    | jq -sc '[.[] | select(
        (.false_verdict_flag // .falseVerdictFlag) == "FALSE_PASS" or
        (.false_verdict_flag // .falseVerdictFlag) == "FALSE_PASS_PROXY"
      )] | length')"

  if [[ "$total" -eq 0 ]]; then
    printf '0.00\n'
    return 0
  fi

  # Round to 2 decimals (awk), not integer-truncate — the old %d.%02d path
  # dropped the trailing digit (2/3 → 0.66 instead of 0.67). count/total are
  # integers from jq length; passed via -v so nothing is interpolated.
  # LC_ALL=C pins the decimal separator to '.' — under a comma-decimal
  # LC_NUMERIC, %.2f would emit "0,67" and break downstream parsing.
  LC_ALL=C awk -v c="$count" -v t="$total" 'BEGIN { printf "%.2f\n", c / t }'
}

_should_promote() {
  local tier="${1:?tier required}"
  local n="${2:-10}"

  if [[ "${RND_DISABLE_AUTO_ESCALATION:-}" = "1" ]]; then
    return 1
  fi

  local records total count pct

  records="$(_window "$tier" "$n")"

  if [[ -z "$records" ]]; then
    return 1
  fi

  total="$(printf '%s\n' "$records" | jq -sc 'length')"
  count="$(printf '%s\n' "$records" \
    | jq -sc '[.[] | select(
        (.false_verdict_flag // .falseVerdictFlag) == "FALSE_PASS" or
        (.false_verdict_flag // .falseVerdictFlag) == "FALSE_PASS_PROXY"
      )] | length')"

  if [[ "$total" -eq 0 ]]; then
    return 1
  fi

  pct=$(( count * 100 / total ))

  [[ "$pct" -ge 20 ]]
}

_promote_tier() {
  local tier="${1:?tier required}"

  case "$tier" in
    LOW)    printf 'NORMAL\n' ;;
    NORMAL) printf 'HIGH\n' ;;
    HIGH)   printf 'HIGH\n' ;;
    *)
      printf 'calibration.sh: unknown tier: %s\n' "$tier" >&2
      return 1
      ;;
  esac
}

_task_type_window() {
  local type="${1:?task_type required}"
  local n="${2:-10}"
  local calib
  calib="$(_calib_file)"

  if [[ ! -f "$calib" ]]; then
    printf '' ; return 0
  fi

  jq -c --arg type "$type" 'select(.task_type == $type)' "$calib" | tail -n "$n"
}

_assertion_id_window() {
  local assertion_id="${1:?assertion_id required}"
  local n="${2:-10}"
  local calib
  calib="$(_calib_file)"

  if [[ ! -f "$calib" ]]; then
    printf '' ; return 0
  fi

  jq -c --arg id "$assertion_id" 'select(.assertion_id == $id)' "$calib" | tail -n "$n"
}

# Collapse per-finding rows to one clean/dirty verdict per (session,shape),
# order sessions chronologically, and count the TRAILING consecutive-clean run.
# A session is dirty iff any of its rows for <shape> has review_found == true.
# Sorting key is the sortable session_id (YYYYMMDD-HHMMSS-xxxx); when a session's
# id is missing it falls back to its timestamp so order stays chronological.
# Streak as an integer: collapse → order → count trailing clean run.
_streak() {
  local shape="${1:?shape required}"
  local postreview
  postreview="$(_postreview_file)"

  if [[ ! -f "$postreview" ]]; then
    printf '0'
    return 0
  fi

  # -R + fromjson? tolerates malformed lines (skips them) the same way the
  # stats SQL views guard on json_valid, rather than aborting the whole parse.
  jq -rRn --arg shape "$shape" '
    [ inputs | fromjson? | select(.shape == $shape) ]
    | group_by(.session_id)
    | map({
        key:   (.[0].session_id // .[0].timestamp // ""),
        dirty: (any(.[]; .review_found == true))
      })
    | sort_by(.key)
    | reverse
    | reduce .[] as $s ({n: 0, done: false};
        if .done or $s.dirty then {n: .n, done: true}
        else {n: (.n + 1), done: false} end)
    | .n
  ' "$postreview" 2>/dev/null || printf '0'
}

# Print the trailing consecutive-clean run count for <shape>.
_print_consecutive_clean() {
  local shape="${1:?shape required}"
  printf '%s\n' "$(_streak "$shape")"
}

# Exit 0 + "expert" iff streak >= N_EXPERT_CONSECUTIVE_CLEAN; else "novice <n>".
_validity() {
  local shape="${1:?shape required}"
  local streak
  streak="$(_streak "$shape")"

  if [[ "$streak" -ge "$N_EXPERT_CONSECUTIVE_CLEAN" ]]; then
    printf 'expert\n'
    return 0
  fi

  printf 'novice %s\n' "$streak"
  return 1
}

subcommand="${1:-}"

case "$subcommand" in
  --help)
    _usage
    ;;
  window)
    shift
    _window "$@"
    ;;
  false_pass_rate)
    shift
    _false_pass_rate "$@"
    ;;
  should_promote)
    shift
    _should_promote "$@"
    ;;
  promote_tier)
    shift
    _promote_tier "$@"
    ;;
  task_type_window)
    shift
    _task_type_window "$@"
    ;;
  assertion_id_window)
    shift
    _assertion_id_window "$@"
    ;;
  consecutive_clean)
    shift
    _print_consecutive_clean "$@"
    ;;
  validity)
    shift
    _validity "$@"
    ;;
  *)
    _usage >&2
    exit 1
    ;;
esac
