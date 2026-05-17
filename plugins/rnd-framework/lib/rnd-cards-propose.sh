#!/usr/bin/env bash
# rnd-cards-propose.sh — Scan calibration.jsonl for recurring FAIL verdict
# clusters and surface clusters with >= 3 members as draft card markdown.
#
# Usage:
#   rnd-cards-propose.sh [--calibration=<path>] [--threshold=<float>] [--min-cluster=<int>]
#
#   --calibration=<path>   Path to calibration.jsonl (default: $CLAUDE_PLUGIN_DATA/calibration.jsonl
#                          or rnd-dir.sh --calibration fallback)
#   --threshold=<float>    Jaccard similarity threshold for linking (default: 0.4)
#   --min-cluster=<int>    Minimum cluster size to surface (default: 3)
#   --help                 Print this usage and exit 0
#
# Output:
#   Prints draft card markdown for each qualifying cluster to stdout.
#   Nothing is written to disk.
#
# Environment:
#   CLAUDE_PLUGIN_DATA   Preferred calibration.jsonl location (falls back to rnd-dir.sh).
#   CLAUDE_PLUGIN_ROOT   Required for rnd-dir.sh fallback path resolution.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_usage() {
  printf 'Usage: rnd-cards-propose.sh [--calibration=<path>] [--threshold=<float>] [--min-cluster=<int>]\n\n'
  printf 'Options:\n'
  printf '  --calibration=<path>   Path to calibration.jsonl\n'
  printf '  --threshold=<float>    Jaccard similarity threshold (default: 0.4)\n'
  printf '  --min-cluster=<int>    Minimum cluster size to surface (default: 3)\n'
  printf '  --help                 Print this usage\n'
}

_calib_file() {
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    printf '%s/calibration.jsonl' "$CLAUDE_PLUGIN_DATA"
  else
    "${_SCRIPT_DIR}/rnd-dir.sh" --calibration
  fi
}

# Produce a JSON array of {id, feedback, ngrams} objects from calibration.jsonl.
# Filters to FAIL/NEEDS_ITERATION records with non-empty feedback.
_extract_records() {
  local calib_path="$1"

  if [[ ! -f "$calib_path" ]]; then
    printf '[]\n'
    return 0
  fi

  jq -sc '
    [
      to_entries[]
      | .key as $idx
      | .value
      | select(
          (.verdict == "FAIL" or .verdict == "NEEDS_ITERATION")
          and (.feedback != null)
          and (.feedback | type) == "string"
          and (.feedback | length) > 0
        )
      | {
          id: $idx,
          feedback: .feedback,
          ngrams: (
            .feedback
            | ascii_downcase
            | split(" ")
            | map(select(length > 0))
            | . as $words
            | if ($words | length) < 4 then
                []
              else
                [ range(($words | length) - 3) ]
                | map(
                    [$words[.], $words[. + 1], $words[. + 2], $words[. + 3]]
                    | join(" ")
                  )
              end
          )
        }
    ]
  ' "$calib_path"
}

# Compute Jaccard similarity between two 4-gram arrays (represented as JSON arrays).
_jaccard() {
  local a="$1"
  local b="$2"

  jq -n \
    --argjson a "$a" \
    --argjson b "$b" \
    '
      ($a | unique) as $sa
      | ($b | unique) as $sb
      | ([ $sa[], $sb[] ] | unique | length) as $union_len
      | if $union_len == 0 then 0.0
        else
          ([ $sa[] ] as $set_a |
           [ $sb[] | select(. as $x | $set_a | any(. == $x)) ] | length) as $inter_len
          | ($inter_len / $union_len)
        end
    '
}

# Build a union-find structure (bash associative array) and cluster records.
# Accepts JSON array of {id, feedback, ngrams} and threshold as float.
_cluster() {
  local records="$1"
  local threshold="$2"
  local min_cluster="$3"

  local count
  count="$(printf '%s' "$records" | jq 'length')"

  if [[ "$count" -lt 2 ]]; then
    return 0
  fi

  # Extract ngrams for each record into shell variables
  declare -a ngrams_arr
  declare -a feedback_arr

  local i
  for (( i = 0; i < count; i++ )); do
    ngrams_arr[$i]="$(printf '%s' "$records" | jq -c --argjson i "$i" '.[$i].ngrams')"
    feedback_arr[$i]="$(printf '%s' "$records" | jq -r --argjson i "$i" '.[$i].feedback')"
  done

  # Union-find: parent array (bash associative array keyed by index)
  declare -A parent
  for (( i = 0; i < count; i++ )); do
    parent[$i]=$i
  done

  _find() {
    local x="$1"
    while [[ "${parent[$x]}" != "$x" ]]; do
      parent[$x]="${parent[${parent[$x]}]}"
      x="${parent[$x]}"
    done
    printf '%s' "$x"
  }

  _union() {
    local rx ry
    rx="$(_find "$1")"
    ry="$(_find "$2")"
    if [[ "$rx" != "$ry" ]]; then
      parent[$ry]=$rx
    fi
  }

  # Compute pairwise Jaccard and union if above threshold
  local j sim result
  for (( i = 0; i < count - 1; i++ )); do
    for (( j = i + 1; j < count; j++ )); do
      # Skip if both have empty ngrams
      if [[ "${ngrams_arr[$i]}" == "[]" ]] && [[ "${ngrams_arr[$j]}" == "[]" ]]; then
        continue
      fi

      sim="$(_jaccard "${ngrams_arr[$i]}" "${ngrams_arr[$j]}")"

      # Compare floats: multiply by 1000 and compare as integers
      local sim_int thresh_int
      sim_int="$(printf '%s' "$sim" | jq -r '(. * 1000) | round | tostring')"
      thresh_int="$(printf '%s' "$threshold" | jq -r '(tonumber * 1000) | round | tostring')"

      if [[ "$sim_int" -ge "$thresh_int" ]]; then
        _union "$i" "$j"
      fi
    done
  done

  # Group indices by root
  declare -A groups
  for (( i = 0; i < count; i++ )); do
    local root
    root="$(_find "$i")"
    groups[$root]="${groups[$root]:-} $i"
  done

  # Output qualifying clusters
  local cluster_num=0
  for root in "${!groups[@]}"; do
    local members
    members=(${groups[$root]})
    local size="${#members[@]}"

    if [[ "$size" -lt "$min_cluster" ]]; then
      continue
    fi

    cluster_num=$(( cluster_num + 1 ))

    # Collect ngrams across all cluster members to find shared ones
    local all_ngrams="[]"
    local member_feedbacks=()

    for m in "${members[@]}"; do
      all_ngrams="$(jq -n \
        --argjson existing "$all_ngrams" \
        --argjson new "${ngrams_arr[$m]}" \
        '$existing + $new')"
      member_feedbacks+=("${feedback_arr[$m]}")
    done

    # Shared ngrams: appear in at least half the cluster members
    local min_support=$(( (size + 1) / 2 ))
    local shared_ngrams
    shared_ngrams="$(printf '%s' "$all_ngrams" | jq -r \
      --argjson min_support "$min_support" \
      '
        group_by(.)
        | map(select(length >= $min_support) | .[0])
        | sort[]
      ')"

    # Sample feedbacks (up to 2)
    local sample1="${member_feedbacks[0]:-}"
    local sample2="${member_feedbacks[1]:-}"

    printf '## Cluster %d\n\n' "$cluster_num"
    printf '**Cluster size:** %d\n\n' "$size"

    if [[ -n "$shared_ngrams" ]]; then
      printf '**Shared patterns:**\n'
      printf '%s' "$shared_ngrams" | head -5 | while IFS= read -r gram; do
        printf -- '- `%s`\n' "$gram"
      done
      printf '\n'
    fi

    printf '**Sample feedback:**\n\n'
    printf '> %s\n\n' "$sample1"

    if [[ -n "$sample2" ]] && [[ "$sample2" != "$sample1" ]]; then
      printf '> %s\n\n' "$sample2"
    fi

    printf '**Draft card scaffold:**\n\n'
    printf '```markdown\n'
    printf '%s\n' '---'
    printf 'role: builder\n'
    printf 'lang: generic\n'
    printf 'tags: []\n'
    printf 'applicable_task_types: []\n'
    printf '%s\n\n' '---'
    printf '# (Edit: Card title here)\n\n'
    printf '(Edit: Card body — guidance to address the recurring failure pattern)\n'
    printf '```\n\n'
    printf '%s\n\n' '---'
  done

  if [[ "$cluster_num" -eq 0 ]]; then
    printf 'No clusters of size >= %d found at threshold %.2f.\n' "$min_cluster" "$threshold"
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

_calib_path=""
_threshold="0.4"
_min_cluster="3"

for arg in "$@"; do
  case "$arg" in
    --help)
      _usage
      exit 0
      ;;
    --calibration=*)
      _calib_path="${arg#--calibration=}"
      ;;
    --threshold=*)
      _threshold="${arg#--threshold=}"
      ;;
    --min-cluster=*)
      _min_cluster="${arg#--min-cluster=}"
      ;;
    *)
      printf 'rnd-cards-propose.sh: unknown argument: %s\n' "$arg" >&2
      _usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$_calib_path" ]]; then
  _calib_path="$(_calib_file)"
fi

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

records="$(_extract_records "$_calib_path")"
_cluster "$records" "$_threshold" "$_min_cluster"
