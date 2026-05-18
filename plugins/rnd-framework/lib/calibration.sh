#!/usr/bin/env bash
# calibration.sh — Helpers for the calibration auto-escalation loop.
#
# Advisory contract: collapse_eligible and related mode-window subcommands are
# advisory only — they do NOT change dispatch behavior. They accumulate telemetry
# and emit informational audit events. Any dispatch change requires a separate task.
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
#       Print the promoted tier: LOW->MEDIUM, MEDIUM->HIGH, HIGH->HIGH, HIGH-PII->HIGH-PII.
#       Exit non-zero for unknown tiers.
#
#   calibration.sh task_type_window <type> [N=10]
#       Print last N calibration.jsonl records filtered by task_type == <type>.
#       task_type values: refactor | new-feature | bugfix | docs | config | infra
#
#   calibration.sh mode_window <task_type> <verification_mode> [N=30]
#       Print last N calibration.jsonl records filtered by task_type == <task_type>
#       AND verification_mode == <verification_mode>. Records missing verification_mode
#       are treated as "prose" for backward compatibility.
#
#   calibration.sh mode_false_pass_rate <task_type> <verification_mode> [N=30]
#       Print the false-PASS rate as a percent (0.00-100.00) for the given
#       (task_type, verification_mode) window.
#
#   calibration.sh collapse_eligible <task_type>
#       Returns "eligible" if property-mode false-PASS rate over the last 30 entries
#       is <= 50% of prose-mode false-PASS rate AND both windows have >= 10 entries.
#       Otherwise returns "ineligible: <reason>". When eligible, also emits a
#       verifier_collapse_eligible audit event (advisory — does NOT change dispatch).
#
#   calibration.sh --help
#       Print this usage and exit 0.
#
# Environment:
#   RND_DISABLE_AUTO_ESCALATION  Set to "1" to make should_promote always exit non-zero.
#   CLAUDE_PLUGIN_DATA           Preferred calibration.jsonl location (falls back to rnd-dir.sh).
#   CLAUDE_PLUGIN_ROOT           Required for rnd-dir.sh fallback path resolution.
#   RND_DIR                      Required for collapse_eligible audit event emission.

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
  printf '  window <tier> [N=10]                          Print last N records for <tier> (LOW|MEDIUM|HIGH|HIGH-PII)\n'
  printf '  false_pass_rate <tier> [N=10]                 Print false-PASS rate (0.00-1.00) for <tier>\n'
  printf '  should_promote <tier> [N=10]                  Exit 0 if rate >= 0.20 and escalation not disabled\n'
  printf '  promote_tier <tier>                           Print promoted tier (LOW->MEDIUM, MEDIUM->HIGH, HIGH->HIGH, HIGH-PII->HIGH-PII)\n'
  printf '  task_type_window <type> [N=10]                Print last N records filtered by task_type\n'
  printf '  mode_window <task_type> <mode> [N=30]         Print last N records for (task_type, verification_mode) pair\n'
  printf '  mode_false_pass_rate <task_type> <mode> [N=30] Print false-PASS rate as percent (0.00-100.00)\n'
  printf '  collapse_eligible <task_type>                 Print eligible/ineligible; emits advisory audit event when eligible\n'
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
    LOW)      printf 'MEDIUM\n' ;;
    MEDIUM)   printf 'HIGH\n' ;;
    HIGH)     printf 'HIGH\n' ;;
    HIGH-PII) printf 'HIGH-PII\n' ;;
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

# _calib_mode_window: single-pass jq filter for (task_type, verification_mode) pairs.
# Records without a verification_mode field are treated as "prose" for backward compat.
_calib_mode_window() {
  local type="${1:?task_type required}"
  local mode="${2:?verification_mode required}"
  local n="${3:-30}"
  local calib
  calib="$(_calib_file)"

  if [[ ! -f "$calib" ]]; then
    printf '' ; return 0
  fi

  jq -c --arg type "$type" --arg mode "$mode" \
    'select(
      .task_type == $type
      and ((.verification_mode // "prose") == $mode)
    )' "$calib" | tail -n "$n"
}

_mode_window() {
  _calib_mode_window "$@"
}

_mode_false_pass_rate() {
  local type="${1:?task_type required}"
  local mode="${2:?verification_mode required}"
  local n="${3:-30}"
  local records total count scaled

  records="$(_calib_mode_window "$type" "$mode" "$n")"

  if [[ -z "$records" ]]; then
    printf '0.00\n'
    return 0
  fi

  total="$(printf '%s\n' "$records" | jq -sc 'length')"

  if [[ "$total" -eq 0 ]]; then
    printf '0.00\n'
    return 0
  fi

  count="$(printf '%s\n' "$records" \
    | jq -sc '[.[] | select(.falseVerdictFlag == "FALSE_PASS" or .falseVerdictFlag == "FALSE_PASS_PROXY")] | length')"

  # Compute percent × 100 in integer arithmetic, then format as NN.NN
  scaled=$(( count * 10000 / total ))
  printf '%d.%02d\n' $(( scaled / 100 )) $(( scaled % 100 ))
}

_collapse_eligible() {
  local type="${1:?task_type required}"
  local n=30

  local prose_records property_records prose_total property_total
  prose_records="$(_calib_mode_window "$type" "prose" "$n")"
  property_records="$(_calib_mode_window "$type" "property" "$n")"

  prose_total=0
  property_total=0

  [[ -n "$prose_records" ]] && prose_total="$(printf '%s\n' "$prose_records" | jq -sc 'length')"
  [[ -n "$property_records" ]] && property_total="$(printf '%s\n' "$property_records" | jq -sc 'length')"

  if [[ "$prose_total" -lt 10 || "$property_total" -lt 10 ]]; then
    printf 'ineligible: insufficient samples\n'
    return 0
  fi

  local prose_count property_count prose_scaled property_scaled
  prose_count="$(printf '%s\n' "$prose_records" \
    | jq -sc '[.[] | select(.falseVerdictFlag == "FALSE_PASS" or .falseVerdictFlag == "FALSE_PASS_PROXY")] | length')"
  property_count="$(printf '%s\n' "$property_records" \
    | jq -sc '[.[] | select(.falseVerdictFlag == "FALSE_PASS" or .falseVerdictFlag == "FALSE_PASS_PROXY")] | length')"

  # Scale both rates to integers (× 10000) then compare. Eligible when
  # property_rate ≤ 50% of prose_rate, i.e. property_scaled ≤ prose_scaled / 2.
  prose_scaled=$(( prose_count * 10000 / prose_total ))
  property_scaled=$(( property_count * 10000 / property_total ))

  local threshold=$(( prose_scaled / 2 ))

  if [[ "$property_scaled" -le "$threshold" ]]; then
    local prose_pct property_pct
    prose_pct="$(printf '%d.%02d' $(( prose_scaled / 100 )) $(( prose_scaled % 100 )))"
    property_pct="$(printf '%d.%02d' $(( property_scaled / 100 )) $(( property_scaled % 100 )))"

    bash "${_SCRIPT_DIR}/audit-event.sh" \
      "verifier_collapse_eligible" \
      "" \
      "task_type:${type}:prose_rate:${prose_pct}:property_rate:${property_pct}" 2>/dev/null || true

    printf 'eligible\n'
  else
    printf 'ineligible: property_rate not below threshold\n'
  fi
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
  mode_window)
    shift
    _mode_window "$@"
    ;;
  mode_false_pass_rate)
    shift
    _mode_false_pass_rate "$@"
    ;;
  collapse_eligible)
    shift
    _collapse_eligible "$@"
    ;;
  *)
    _usage >&2
    exit 1
    ;;
esac
