#!/usr/bin/env bash
# hooks/evidence-locking-gate.sh — PreToolUse Write|Edit hook.
# Intercepts verifier writes of wave-N-verdict-map.json and validates the
# evidence array in two passes:
#   (1) Form  — rejects empty, missing, or trivial evidence arrays.
#   (2) Substance — extracts a citable token from each form-passing item and
#       confirms it exists in the union corpus (session dir + project repo
#       root), excluding barrier dirs (verifications/builds/briefs/cleanup).
#       Evidence items with no extractable token are exempt.
# Emits exactly one gate_fired audit event per blocked write (first offender).
#
# Schema knobs (trivial-token denylist, minimum length, citation markers,
# substance exclude-dirs) are sourced from lib/verdict-map-schema.json (SSOT).
# Hardcoded fallbacks are used only if the schema file is missing or unreadable.

# shellcheck source=./lib.sh
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/lib.sh"

readonly VERDICT_MAP_SCHEMA_PATH="${HOOK_DIR}/../lib/verdict-map-schema.json"

# ---------------------------------------------------------------------------
# Source schema constants from the SSOT
# ---------------------------------------------------------------------------

TRIVIAL_TOKENS_JSON=""
MIN_EVIDENCE_LENGTH=""
CITATION_MARKERS_JSON=""
SUBSTANCE_EXCLUDE_DIRS_JSON=""

if [[ -r "$VERDICT_MAP_SCHEMA_PATH" ]]; then
  TRIVIAL_TOKENS_JSON="$(jq -c '."x-trivial-tokens"' "$VERDICT_MAP_SCHEMA_PATH" 2>/dev/null || true)"
  MIN_EVIDENCE_LENGTH="$(jq -r '."x-min-evidence-length"' "$VERDICT_MAP_SCHEMA_PATH" 2>/dev/null || true)"
  CITATION_MARKERS_JSON="$(jq -c '."x-evidence-citation-markers"' "$VERDICT_MAP_SCHEMA_PATH" 2>/dev/null || true)"
  SUBSTANCE_EXCLUDE_DIRS_JSON="$(jq -c '."x-substance-exclude-dirs"' "$VERDICT_MAP_SCHEMA_PATH" 2>/dev/null || true)"
fi

# Hardcoded fallbacks (kept aligned with the schema).
[[ -n "$TRIVIAL_TOKENS_JSON" && "$TRIVIAL_TOKENS_JSON" != "null" ]] || \
  TRIVIAL_TOKENS_JSON='["","n/a","na","none","ok","passed","fail","true","false","yes","no","done","ran tests","compiles","no errors","looks good","lgtm","tbd","todo"]'
[[ -n "$MIN_EVIDENCE_LENGTH" && "$MIN_EVIDENCE_LENGTH" != "null" ]] || \
  MIN_EVIDENCE_LENGTH="40"
[[ -n "$CITATION_MARKERS_JSON" && "$CITATION_MARKERS_JSON" != "null" ]] || \
  CITATION_MARKERS_JSON='[":","\/","`","\"","<"]'
[[ -n "$SUBSTANCE_EXCLUDE_DIRS_JSON" && "$SUBSTANCE_EXCLUDE_DIRS_JSON" != "null" ]] || \
  SUBSTANCE_EXCLUDE_DIRS_JSON='["verifications","builds","briefs","cleanup"]'

# ---------------------------------------------------------------------------
# Substance pass helpers
# ---------------------------------------------------------------------------

# Extract the longest citable token from an evidence string.
# Priority: longest backtick-quoted span > longest double-quoted span >
#           longest contiguous run containing '/'.
# Prints the token to stdout. Prints nothing (exempt) when no token is found.
_extract_citable_token() {
  local s="$1"

  # Longest backtick-quoted span.
  local best=""
  local remainder="$s"
  while [[ "$remainder" == *"\`"*"\`"* ]]; do
    local after_open="${remainder#*\`}"
    local candidate="${after_open%%\`*}"
    remainder="${after_open#*\`}"
    if [[ "${#candidate}" -gt "${#best}" ]]; then
      best="$candidate"
    fi
  done
  if [[ -n "$best" ]]; then
    printf '%s' "$best"
    return
  fi

  # Longest double-quoted span.
  remainder="$s"
  while [[ "$remainder" == *'"'*'"'* ]]; do
    local after_open="${remainder#*\"}"
    local candidate="${after_open%%\"*}"
    remainder="${after_open#*\"}"
    if [[ "${#candidate}" -gt "${#best}" ]]; then
      best="$candidate"
    fi
  done
  if [[ -n "$best" ]]; then
    printf '%s' "$best"
    return
  fi

  # Longest contiguous run containing '/'.
  # Split on whitespace, keep runs that contain '/', pick the longest.
  local word longest=""
  for word in $s; do
    if [[ "$word" == *"/"* ]]; then
      if [[ "${#word}" -gt "${#longest}" ]]; then
        longest="$word"
      fi
    fi
  done

  if [[ -n "$longest" ]]; then
    # Normalize a path-like token: drop a trailing line[:col] reference
    # (path:42, path:42:7) and one trailing sentence-punctuation char, so the
    # path core matches the corpus. ':' is a citation marker, so 'path:line'
    # is a legitimate evidence form the form pass already accepts.
    while [[ "$longest" =~ :[0-9]+$ ]]; do
      longest="${longest%:*}"
    done

    case "$longest" in
      *[.,\;\)]) longest="${longest%?}" ;;
    esac

    printf '%s' "$longest"
  fi
  # No token found → prints nothing (item is exempt).
}

# Build the in-memory substance corpus.
# Sets the global SUBSTANCE_CORPUS variable.
# Sources: (1) session dir (from active_session_dir), excluding x-substance-exclude-dirs;
#          (2) git-tracked project files from the repo root, excluding those same dirs.
# On git-failure, corpus falls back to session-only (documented degradation, not a crash).
_build_substance_corpus() {
  # Convert JSON exclude-dirs array to bash array.
  local exclude_dirs=()
  while IFS= read -r d; do
    exclude_dirs+=("$d")
  done < <(printf '%s' "$SUBSTANCE_EXCLUDE_DIRS_JSON" | jq -r '.[]' 2>/dev/null || true)

  SUBSTANCE_CORPUS=""

  # Session root.
  local session_dir
  session_dir="$(active_session_dir 2>/dev/null || true)"

  if [[ -n "$session_dir" && -d "$session_dir" ]]; then
    # Build prune arguments for find.
    local prune_args=()
    local d
    for d in "${exclude_dirs[@]}"; do
      prune_args+=(-path "${session_dir}/${d}" -prune -o)
    done

    local file
    while IFS= read -r -d '' file; do
      [[ -f "$file" ]] || continue
      # Include both the file path (so relative-path tokens match) and its contents.
      SUBSTANCE_CORPUS+=" ${file} "
      SUBSTANCE_CORPUS+="$(cat "$file" 2>/dev/null || true)"
    done < <(find "$session_dir" "${prune_args[@]}" -type f -print0 2>/dev/null || true)
  fi

  # Project repo root (git-tracked files only — bounded, no .git/node_modules).
  local repo_root
  repo_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"

  if [[ -n "$repo_root" && -d "$repo_root" ]]; then
    # Build path-prefix exclusion patterns for grep.
    local exclude_pattern=""
    local d
    for d in "${exclude_dirs[@]}"; do
      exclude_pattern="${exclude_pattern}${exclude_pattern:+|}^${d}/"
    done

    local tracked_files
    tracked_files="$(git -C "$repo_root" ls-files 2>/dev/null || true)"

    if [[ -n "$exclude_pattern" ]]; then
      tracked_files="$(printf '%s\n' "$tracked_files" | grep -Ev "$exclude_pattern" 2>/dev/null || true)"
    fi

    local rel_path
    while IFS= read -r rel_path; do
      [[ -n "$rel_path" ]] || continue
      local abs_path="${repo_root}/${rel_path}"
      [[ -f "$abs_path" ]] || continue
      # Include both the file path (so path-like tokens match) and its contents.
      SUBSTANCE_CORPUS+=" ${abs_path} "
      SUBSTANCE_CORPUS+="$(cat "$abs_path" 2>/dev/null || true)"
    done <<< "$tracked_files"
  fi
}

# ---------------------------------------------------------------------------
# Path check: verdict-map files only
# ---------------------------------------------------------------------------

_is_verdict_map_path() {
  local path="$1"
  is_plugin_artifact_path "$path" || return 1
  [[ "$path" == */verifications/wave-*-verdict-map.json ]]
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_input
file_path="$(extract_file_path "$TOOL_INPUT")"
agent_lower="$(_lower "${AGENT_TYPE}")"

# Only intercept writes of verdict-map files by the verifier agent.
_is_verdict_map_path "$file_path" || exit 0
[[ "$agent_lower" == *"verifier"* ]] || exit 0

# Extract the content being written from the tool input.
new_content="$(printf '%s' "$TOOL_INPUT" | jq -r '.new_file // .content // ""' 2>/dev/null || true)"

if [[ -z "$new_content" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Single jq pass: walk every assertion entry, find the first offender.
# An entry is invalid when:
#   (a) it lacks an "evidence" key                         tag: "missing"
#   (b) evidence is an empty array                         tag: "empty"
#   (c) any evidence item is trivial (every-not-any)       tag: "trivial"
#
# Non-trivial item: length >= x-min-evidence-length OR contains any
# x-evidence-citation-markers character. Trivial-token denylist applies
# only when neither structural test passes.
# ---------------------------------------------------------------------------

offender="$(printf '%s' "$new_content" | jq -r \
  --argjson trivial_tokens "$TRIVIAL_TOKENS_JSON" \
  --argjson min_len "$MIN_EVIDENCE_LENGTH" \
  --argjson markers "$CITATION_MARKERS_JSON" \
  '
  def has_any_marker:
    . as $s | any($markers[]; . as $m | ($s | index($m)) != null);

  def item_trivial:
    . as $s |
    if ($s | length) >= $min_len then false
    elif ($s | has_any_marker) then false
    else ($s | ascii_downcase) as $lower |
      any($trivial_tokens[]; . == $lower)
      or ($s | ltrimstr(" ") | rtrimstr(" ") | length) == 0
    end;

  first(
    to_entries[]
    | .key as $id
    | .value
    | if type != "object" then empty
      elif has("evidence") | not then {id: $id, tag: "missing"}
      elif (.evidence | (type != "array" or length == 0)) then {id: $id, tag: "empty"}
      elif any(.evidence[]; item_trivial) then {id: $id, tag: "trivial"}
      else empty
      end
  )
  | "\(.id)\t\(.tag)"
' 2>/dev/null || true)"

if [[ -n "$offender" ]]; then
  offender_id="${offender%%$'\t'*}"
  violation_tag="${offender##*$'\t'}"

  # Emit exactly one audit event for the form offender.
  session_dir="$(active_session_dir 2>/dev/null || true)"

  if [[ -n "$session_dir" ]]; then
    RND_DIR="$session_dir" bash "${HOOK_DIR}/../lib/audit-event.sh" \
      "gate_fired" "$offender_id" "evidence_locking_gate" 2>/dev/null || true
  fi

  block_msg "evidence-locking-gate: verdict-map write blocked.

Assertion ID : ${offender_id}
Violation    : ${violation_tag}
Schema SSOT  : plugins/rnd-framework/lib/verdict-map-schema.json

Every assertion entry in the verdict map must include a non-empty evidence
array where every item is non-trivial (length >= ${MIN_EVIDENCE_LENGTH} or
contains a citation marker such as ':', '/', backtick, quote, or '<').

Trivial-token denylist, minimum length, and citation markers are defined in
the x-trivial-tokens, x-min-evidence-length, and x-evidence-citation-markers
fields of verdict-map-schema.json.

Re-emit the verdict map with substantive, citable evidence for '${offender_id}'."
fi

# ---------------------------------------------------------------------------
# Substance pass: extract citable tokens, confirm each exists in the corpus.
# Runs only when the form pass found no offender.
# ---------------------------------------------------------------------------

# Extract all evidence strings from the form-passing content, keyed by assertion ID.
# Output: lines of  <assertion_id><TAB><evidence_item>
assertion_evidence="$(printf '%s' "$new_content" | jq -r \
  'to_entries[]
   | .key as $id
   | .value.evidence[]?
   | [$id, .] | @tsv' 2>/dev/null || true)"

if [[ -z "$assertion_evidence" ]]; then
  exit 0
fi

# Token cache: dedup lookups across assertions via _token_checked / _token_present maps.
declare -A _token_present
declare -A _token_checked

_build_substance_corpus

sub_offender_id=""
sub_missing_token=""

while IFS=$'\t' read -r ass_id evidence_item; do
  [[ -n "$ass_id" ]] || continue

  token="$(_extract_citable_token "$evidence_item")"

  [[ -n "$token" ]] || continue  # exempt: no citable token

  # Look up in cache first.
  if [[ -v _token_checked["$token"] ]]; then
    if [[ "${_token_present["$token"]:-}" != "1" ]]; then
      sub_offender_id="$ass_id"
      sub_missing_token="$token"
      break
    fi
    continue
  fi

  _token_checked["$token"]=1
  if [[ "$SUBSTANCE_CORPUS" == *"$token"* ]]; then
    _token_present["$token"]="1"
  else
    _token_present["$token"]="0"
    sub_offender_id="$ass_id"
    sub_missing_token="$token"
    break
  fi
done <<< "$assertion_evidence"

if [[ -z "$sub_offender_id" ]]; then
  exit 0
fi

# Emit exactly one audit event for the substance offender.
session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -n "$session_dir" ]]; then
  RND_DIR="$session_dir" bash "${HOOK_DIR}/../lib/audit-event.sh" \
    "gate_fired" "$sub_offender_id" "evidence_locking_gate" 2>/dev/null || true
fi

block_msg "evidence-locking-gate: SUBSTANCE FAILURE — verdict-map write blocked.

Assertion ID  : ${sub_offender_id}
Missing token : ${sub_missing_token}
Schema SSOT   : plugins/rnd-framework/lib/verdict-map-schema.json

The citable token extracted from an evidence item in '${sub_offender_id}' does
not appear in any searched artifact (session dir + project repo root, excluding
verifications/, builds/, briefs/, cleanup/).

The evidence must cite a token — a path, quoted string, or backtick span —
that is present in the verified artifact corpus. Update the evidence for
'${sub_offender_id}' to reference an observable artifact."
