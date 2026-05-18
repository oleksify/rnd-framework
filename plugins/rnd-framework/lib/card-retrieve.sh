#!/usr/bin/env bash
# card-retrieve.sh — Deterministic tag-overlap card retrieval.
#
# Usage:
#   card-retrieve.sh --role=<role> [--task-type=<type>] [--tags=<t1,t2>]
#                    [--max=<N>] [--cards-root=<dir>] [--help]
#
#   Returns the top-N matching card paths for a (role, task_type, tags) query,
#   one per line.
#
# Scoring:
#   score = (# shared tags between query and card)
#         + (1 if task_type is in card's applicable_task_types, else 0)
#   Cards whose role != <role> are excluded entirely.
#
# Tiebreaker: score DESC, then card id ASC (lexicographic).
#
# Environment:
#   RND_CARDS_MAX_PER_SPAWN   Default max when --max is not supplied (default 3).

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_usage() {
  printf 'Usage: card-retrieve.sh --role=<role> [options]\n\n'
  printf 'Flags:\n'
  printf '  --role=<role>          Role to filter cards by (required)\n'
  printf '  --task-type=<type>     Task type for bonus scoring (optional)\n'
  printf '  --tags=<t1,t2,...>     Comma-separated query tags (optional)\n'
  printf '  --max=<N>              Maximum cards to return (default: RND_CARDS_MAX_PER_SPAWN or 3)\n'
  printf '  --cards-root=<dir>     Root directory for cards (default: <script-dir>/../cards)\n'
  printf '  --help                 Print this usage and exit 0\n'
}

# ---------------------------------------------------------------------------
# Main: parse flags then run retrieval.
# Flags are parsed via jq from "$@" to avoid shell loops.
# ---------------------------------------------------------------------------

if printf '%s\n' "$@" | grep -qx -- '--help'; then
  _usage
  exit 0
fi

# Parse all --key=value flags at once using jq.
_PARSED="$(
  printf '%s\n' "$@" | jq -Rn '
    [inputs] | map(
      if test("^--[a-z-]+=")
      then (ltrimstr("--") | split("=")) | {(.[0]): (.[1:] | join("="))}
      else empty
      end
    ) | add // {}
  '
)"

_QUERY_ROLE="$(     jq -r '."role"         // ""' <<< "$_PARSED")"
_QUERY_TASK_TYPE="$(jq -r '."task-type"    // ""' <<< "$_PARSED")"
_QUERY_TAGS="$(     jq -r '."tags"         // ""' <<< "$_PARSED")"
_MAX="$(            jq -r '."max"          // ""' <<< "$_PARSED")"
_CARDS_ROOT="$(     jq -r '."cards-root"   // ""' <<< "$_PARSED")"

_CARDS_ROOT="${_CARDS_ROOT:-${_SCRIPT_DIR}/../cards}"

if [[ -z "$_QUERY_ROLE" ]]; then
  printf 'Error: --role is required\n' >&2
  _usage >&2
  exit 1
fi

_MAX="${_MAX:-${RND_CARDS_MAX_PER_SPAWN:-3}}"

# Collect card paths under the role-scoped directory.
mapfile -t _ALL_CARDS < <(
  find "$_CARDS_ROOT/$_QUERY_ROLE" -type f -name 'CARD-*.md' 2>/dev/null | sort
)

if [[ ${#_ALL_CARDS[@]} -eq 0 ]]; then
  exit 0
fi

# Score every card in a single awk pass. Awk parses each file's frontmatter
# (role, id, tags, applicable_task_types), computes shared-tag count + task-type
# bonus, and emits "<score>\t<card_id>\t<path>" for each role-matching card.
# This replaces the previous per-card xargs+jq loop (5 subprocesses × N cards →
# ~600 forks on the live corpus) with a single awk invocation.
awk \
  -v q_role="$_QUERY_ROLE" \
  -v q_type="$_QUERY_TASK_TYPE" \
  -v q_tags="$_QUERY_TAGS" \
  '
  BEGIN {
    n_qt = split(q_tags, qt_arr, /[ \t]*,[ \t]*/)
    for (i = 1; i <= n_qt; i++) {
      t = qt_arr[i]
      if (t != "") qt_set[t] = 1
    }
    current_file = ""
  }

  FNR == 1 {
    if (current_file != "") emit_card()
    current_file = FILENAME
    in_fm = 0; fm_done = 0
    card_role = ""; card_id = ""
    card_tags = ""; card_types = ""
  }

  fm_done { next }

  /^---[ \t]*$/ {
    if (in_fm) { fm_done = 1 } else { in_fm = 1 }
    next
  }

  in_fm {
    if (match($0, /^role:[ \t]*/)) {
      card_role = substr($0, RLENGTH + 1)
    } else if (match($0, /^id:[ \t]*/)) {
      card_id = substr($0, RLENGTH + 1)
    } else if (match($0, /^tags:[ \t]*/)) {
      card_tags = substr($0, RLENGTH + 1)
      sub(/^\[/, "", card_tags); sub(/\][ \t]*$/, "", card_tags)
    } else if (match($0, /^applicable_task_types:[ \t]*/)) {
      card_types = substr($0, RLENGTH + 1)
      sub(/^\[/, "", card_types); sub(/\][ \t]*$/, "", card_types)
    }
  }

  END { if (current_file != "") emit_card() }

  function emit_card(    arr, n, i, shared, types_arr, types_n, type_bonus, score, t) {
    if (card_role != q_role) return

    shared = 0
    n = split(card_tags, arr, /[ \t]*,[ \t]*/)
    for (i = 1; i <= n; i++) {
      t = arr[i]
      if (t != "" && (t in qt_set)) shared++
    }

    type_bonus = 0
    if (q_type != "" && card_types != "") {
      types_n = split(card_types, types_arr, /[ \t]*,[ \t]*/)
      for (i = 1; i <= types_n; i++) {
        if (types_arr[i] == q_type) { type_bonus = 1; break }
      }
    }

    score = shared + type_bonus
    printf "%s\t%s\t%s\n", score, card_id, current_file
  }
  ' \
  "${_ALL_CARDS[@]}" \
  | sort -t $'\t' -k1,1nr -k2,2 \
  | head -n "$_MAX" \
  | cut -f3
