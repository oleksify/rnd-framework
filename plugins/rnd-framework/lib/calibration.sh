#!/usr/bin/env bash
# calibration.sh — Helpers for the calibration auto-escalation loop.
#
# Usage:
#   calibration.sh window <tier> [N=10]
#       Print last N calibration.jsonl records filtered by criticality == <tier>.
#
#   calibration.sh false_pass_rate <tier> [N=10]
#       Print the fraction of records in the window whose falseVerdictFlag is
#       FALSE_PASS or FALSE_PASS_PROXY, formatted as a 2-decimal string (e.g. 0.30).
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

_usage() {
  printf 'Usage: calibration.sh <subcommand> [args]\n\n'
  printf 'Subcommands:\n'
  printf '  window <tier> [N=10]                          Print last N records for <tier> (LOW|NORMAL|HIGH)\n'
  printf '  false_pass_rate <tier> [N=10]                 Print false-PASS rate (0.00-1.00) for <tier>\n'
  printf '  should_promote <tier> [N=10]                  Exit 0 if rate >= 0.20 and escalation not disabled\n'
  printf '  promote_tier <tier>                           Print promoted tier (LOW->NORMAL, NORMAL->HIGH, HIGH->HIGH)\n'
  printf '  task_type_window <type> [N=10]                Print last N records filtered by task_type\n'
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
  local records total count pct

  records="$(_window "$tier" "$n")"

  if [[ -z "$records" ]]; then
    printf '0.00\n'
    return 0
  fi

  total="$(printf '%s\n' "$records" | jq -sc 'length')"
  count="$(printf '%s\n' "$records" \
    | jq -sc '[.[] | select(.falseVerdictFlag == "FALSE_PASS" or .falseVerdictFlag == "FALSE_PASS_PROXY")] | length')"

  if [[ "$total" -eq 0 ]]; then
    printf '0.00\n'
    return 0
  fi

  pct=$(( count * 100 / total ))
  printf '%d.%02d\n' $(( pct / 100 )) $(( pct % 100 ))
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
    | jq -sc '[.[] | select(.falseVerdictFlag == "FALSE_PASS" or .falseVerdictFlag == "FALSE_PASS_PROXY")] | length')"

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
  *)
    _usage >&2
    exit 1
    ;;
esac
