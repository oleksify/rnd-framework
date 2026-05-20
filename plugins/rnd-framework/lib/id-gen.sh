#!/usr/bin/env bash
# id-gen.sh — Mint deterministic kebab-case task and assertion IDs.
#
# Usage:
#   id-gen.sh slug <title>
#       Emit a kebab-case slug (≤32 chars, [a-z0-9-]) to stdout.
#
#   id-gen.sh task <milestone> <task_num> <title>
#       Emit M<milestone>.T<NN>.<slug> where task_num is zero-padded to 2 digits.
#       milestone must be a positive integer.
#
#   id-gen.sh assertion <milestone> <area> <title>
#       Emit M<milestone>.<area>.<slug>.
#       area is passed through unchanged.
#
#   id-gen.sh --help
#       Print this usage and exit 0.
#
# Exit codes:
#   0  Success.
#   2  Invalid arguments (non-numeric milestone, missing args, unknown subcommand).

set -euo pipefail

_usage() {
  printf 'Usage: id-gen.sh <subcommand> [args]\n\n'
  printf 'Subcommands:\n'
  printf '  slug <title>                         Emit kebab-case slug (<=32 chars)\n'
  printf '  task <milestone> <task_num> <title>  Emit M<N>.T<NN>.<slug>\n'
  printf '  assertion <milestone> <area> <title> Emit M<N>.<area>.<slug>\n'
  printf '  --help                               Print this usage and exit 0\n'
}

# slugify: lowercase, non-[a-z0-9] runs → single dash, strip leading/trailing dash, truncate to 32 chars.
# Emits the slug followed by a newline.
slugify() {
  local input="$1"
  printf '%s\n' "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -cs 'a-z0-9\n' '-' \
    | sed 's/-\+/-/g' \
    | sed 's/^-//;s/-$//' \
    | cut -c 1-32 \
    | sed 's/-$//'
}

_cmd_slug() {
  if [[ $# -lt 1 || -z "${1:-}" ]]; then
    printf 'id-gen.sh slug: title argument required\n' >&2
    exit 2
  fi

  local slug
  slug="$(slugify "$1")"

  if [[ -z "$slug" ]]; then
    printf 'id-gen.sh slug: input produced empty slug\n' >&2
    exit 2
  fi

  printf '%s\n' "$slug"
}

_cmd_task() {
  if [[ $# -lt 3 ]]; then
    printf 'id-gen.sh task: requires <milestone> <task_num> <title>\n' >&2
    exit 2
  fi

  local milestone="$1" task_num="$2" title="$3"

  if ! [[ "$milestone" =~ ^[1-9][0-9]*$ ]]; then
    printf 'id-gen.sh task: milestone must be a positive integer, got: %s\n' "$milestone" >&2
    exit 2
  fi

  if ! [[ "$task_num" =~ ^[0-9]+$ ]]; then
    printf 'id-gen.sh task: task_num must be numeric, got: %s\n' "$task_num" >&2
    exit 2
  fi

  local slug
  slug="$(slugify "$title")"
  local padded
  padded="$(printf '%02d' "$task_num")"

  printf 'M%s.T%s.%s\n' "$milestone" "$padded" "$slug"
}

_cmd_assertion() {
  if [[ $# -lt 3 ]]; then
    printf 'id-gen.sh assertion: requires <milestone> <area> <title>\n' >&2
    exit 2
  fi

  local milestone="$1" area="$2" title="$3"

  if ! [[ "$milestone" =~ ^[1-9][0-9]*$ ]]; then
    printf 'id-gen.sh assertion: milestone must be a positive integer, got: %s\n' "$milestone" >&2
    exit 2
  fi

  if ! [[ "$area" =~ ^[a-z][a-z0-9-]*$ ]]; then
    printf 'id-gen.sh assertion: area must be kebab-case [a-z][a-z0-9-]*, got: %s\n' "$area" >&2
    exit 2
  fi

  local slug
  slug="$(slugify "$title")"

  printf 'M%s.%s.%s\n' "$milestone" "$area" "$slug"
}

subcommand="${1:-}"

case "$subcommand" in
  --help)
    _usage
    ;;
  slug)
    shift
    _cmd_slug "$@"
    ;;
  task)
    shift
    _cmd_task "$@"
    ;;
  assertion)
    shift
    _cmd_assertion "$@"
    ;;
  *)
    _usage >&2
    exit 2
    ;;
esac
