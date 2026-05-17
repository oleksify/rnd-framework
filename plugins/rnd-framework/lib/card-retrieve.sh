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

# Extract a single frontmatter field value from a card file.
# Usage: _fm_value <file> <field>
# Prints the raw value after "field: " with leading whitespace stripped.
_fm_value() {
  local file="$1" field="$2" line val
  line="$(grep "^${field}:" "$file" 2>/dev/null || true)"
  val="${line#${field}: }"
  val="${val#${field}:}"
  printf '%s' "${val## }"
}

# Score a single card file against the query and emit a TSV record.
# Emits "<score>\t<card_id>\t<path>" or nothing if role mismatch.
# Called via: export -f _score_card _fm_value; xargs -I{} bash -c '_score_card "$@"' _ {}
#
# Exported globals: _QUERY_ROLE _QUERY_TASK_TYPE _QUERY_TAGS
_score_card() {
  local path="$1"
  local card_role card_id card_tags_raw card_types_raw

  card_role="$(_fm_value "$path" "role")"
  [[ "$card_role" == "$_QUERY_ROLE" ]] || return 0

  card_id="$(_fm_value "$path" "id")"
  card_tags_raw="$(_fm_value "$path" "tags")"
  card_types_raw="$(_fm_value "$path" "applicable_task_types")"

  # Strip surrounding brackets from flow-style YAML lists: [a, b, c] → a, b, c
  card_tags_raw="${card_tags_raw#[}"
  card_tags_raw="${card_tags_raw%]}"
  card_types_raw="${card_types_raw#[}"
  card_types_raw="${card_types_raw%]}"

  # Use jq to compute tag intersection count + task_type bonus — no shell loops.
  # jq receives query tags and card tags as comma-separated strings and computes:
  #   shared_count = length of intersection of the two tag sets
  #   type_bonus   = 1 if query task_type appears in card types, else 0
  local score
  score="$(jq -rn \
    --arg q_tags  "$_QUERY_TAGS" \
    --arg c_tags  "$card_tags_raw" \
    --arg q_type  "$_QUERY_TASK_TYPE" \
    --arg c_types "$card_types_raw" \
    '
      def parse_csv(s):
        if (s | length) == 0 then []
        else s | split(",") | map(gsub("^\\s+|\\s+$"; ""))
        end;

      (parse_csv($q_tags) | map({(.): 1}) | add // {}) as $q_set |
      (parse_csv($c_tags) | map(select($q_set[.])) | length) as $shared |

      (if ($q_type | length) > 0 and ($c_types | length) > 0
        then (parse_csv($c_types) | map(select(. == $q_type)) | length > 0)
        else false
        end) as $type_bonus |

      $shared + (if $type_bonus then 1 else 0 end)
    ')"

  printf '%s\t%s\t%s\n' "$score" "$card_id" "$path"
}

export -f _score_card _fm_value

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

export _QUERY_ROLE _QUERY_TASK_TYPE _QUERY_TAGS

# Collect card paths, score each, sort by score DESC + id ASC, cap, emit paths.
mapfile -t _ALL_CARDS < <(
  find "$_CARDS_ROOT/$_QUERY_ROLE" -type f -name 'CARD-*.md' 2>/dev/null | sort
)

if [[ ${#_ALL_CARDS[@]} -eq 0 ]]; then
  exit 0
fi

printf '%s\n' "${_ALL_CARDS[@]}" \
  | xargs -I{} bash -c '_score_card "$@"' _ {} \
  | sort -t $'\t' -k1,1nr -k2,2 \
  | head -n "$_MAX" \
  | cut -f3
