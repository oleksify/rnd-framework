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

declare -a SUBSTANCE_EXCLUDE_DIRS=()
while IFS= read -r d; do
  SUBSTANCE_EXCLUDE_DIRS+=("$d")
done < <(printf '%s' "$SUBSTANCE_EXCLUDE_DIRS_JSON" | jq -r '.[]' 2>/dev/null || true)

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
  # set -f suspends globbing for the intentional word-split — evidence text is
  # data, and a token like `src/*` must not expand against the cwd.
  local word longest=""
  set -f
  for word in $s; do
    if [[ "$word" == *"/"* ]]; then
      if [[ "${#word}" -gt "${#longest}" ]]; then
        longest="$word"
      fi
    fi
  done
  set +f

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

# Return 0 when the relative token path stays outside excluded dirs.
_path_allowed_for_substance() {
  local rel_path="$1"
  local d

  rel_path="${rel_path#./}"
  [[ "$rel_path" =~ (^|/)\.\.(/|$) ]] && return 1

  for d in "${SUBSTANCE_EXCLUDE_DIRS[@]}"; do
    [[ "$rel_path" == "$d" || "$rel_path" == "$d/"* ]] && return 1
  done

  return 0
}

_session_path_token_exists() {
  local token="$1"
  local session_dir="$2"
  local rel_path candidate

  [[ -n "$session_dir" && -d "$session_dir" ]] || return 1

  if [[ "$token" == "$session_dir/"* ]]; then
    rel_path="${token#"$session_dir"/}"
    candidate="$token"
  elif [[ "$token" == /* ]]; then
    rel_path="${token#/}"
    candidate="${session_dir}/${rel_path}"
  else
    rel_path="${token#./}"
    candidate="${session_dir}/${rel_path}"
  fi

  _path_allowed_for_substance "$rel_path" || return 1
  [[ -f "$candidate" ]]
}

_repo_path_token_exists() {
  local token="$1"
  local repo_root="$2"
  local rel_path

  [[ -n "$repo_root" && -d "$repo_root" ]] || return 1

  if [[ "$token" == "$repo_root/"* ]]; then
    rel_path="${token#"$repo_root"/}"
  elif [[ "$token" == /* ]]; then
    rel_path="${token#/}"
  else
    rel_path="${token#./}"
  fi

  _path_allowed_for_substance "$rel_path" || return 1
  git -C "$repo_root" ls-files --error-unmatch -- "$rel_path" >/dev/null 2>&1 || return 1
  [[ -f "${repo_root}/${rel_path}" ]]
}

_session_content_contains_token() {
  local token="$1"
  local session_dir="$2"
  local prune_args=()
  local d

  [[ -n "$session_dir" && -d "$session_dir" ]] || return 1

  for d in "${SUBSTANCE_EXCLUDE_DIRS[@]}"; do
    prune_args+=(-path "${session_dir}/${d}" -prune -o)
  done

  find "$session_dir" "${prune_args[@]}" -type f -exec grep -F -q -- "$token" {} + >/dev/null 2>&1
}

_repo_content_contains_token() {
  local token="$1"
  local repo_root="$2"
  local pathspecs=(".")
  local d

  [[ -n "$repo_root" && -d "$repo_root" ]] || return 1

  for d in "${SUBSTANCE_EXCLUDE_DIRS[@]}"; do
    pathspecs+=(":(exclude)${d}/**")
  done

  git -C "$repo_root" grep -F -q -e "$token" -- "${pathspecs[@]}" 2>/dev/null
}

_token_present_in_substance() {
  local token="$1"
  local session_dir="$2"
  local repo_root="$3"

  if [[ "$token" == *"/"* ]]; then
    _session_path_token_exists "$token" "$session_dir" && return 0
    _repo_path_token_exists "$token" "$repo_root" && return 0
  fi

  _session_content_contains_token "$token" "$session_dir" && return 0
  _repo_content_contains_token "$token" "$repo_root" && return 0
  return 1
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

# ---------------------------------------------------------------------------
# Content acquisition (per-tool) — FAIL-CLOSED on a matched verifier path.
#
# Write : the document is .content (legacy .new_file kept for older callers).
# Edit  : .new_string is only a FRAGMENT of the document. A fragment must
#         never be evaluated raw — the form-pass jq tolerates parse failure
#         (`|| true`), so a standalone-unparseable fragment would silently
#         pass. Instead the RESULTING document is reconstructed: read the
#         on-disk verdict map and apply the literal substitution
#         old_string -> new_string (quoted bash pattern = literal match;
#         replace_all honored via global substitution).
#
# Policy: once the path matched and the agent is the verifier, an empty
# extraction or an unreconstructable Edit (target file missing/unreadable,
# empty old_string, old_string not found on disk) BLOCKS with exit 2 and one
# gate_fired audit event — never a silent allow. A document the gate cannot
# inspect is treated as unverified evidence.
# ---------------------------------------------------------------------------

_fail_closed() {
  local reason_tag="$1"
  local detail="$2"

  local session_dir
  session_dir="$(active_session_dir 2>/dev/null || true)"

  if [[ -n "$session_dir" ]]; then
    RND_DIR="$session_dir" bash "${HOOK_DIR}/../lib/audit-event.sh" \
      "gate_fired" "$reason_tag" "evidence_locking_gate" 2>/dev/null || true
  fi

  block_msg "evidence-locking-gate: FAIL-CLOSED — verdict-map ${TOOL_NAME:-Write} blocked.

Reason : ${reason_tag}
Detail : ${detail}

The gate could not inspect the resulting verdict-map document, so the
operation is blocked rather than silently allowed. Re-issue the change so
the full document can be reconstructed and validated."
}

if [[ "$TOOL_NAME" == "Edit" ]]; then
  old_string="$(printf '%s' "$TOOL_INPUT" | jq -r '.old_string // ""' 2>/dev/null || true)"
  new_string="$(printf '%s' "$TOOL_INPUT" | jq -r '.new_string // ""' 2>/dev/null || true)"
  replace_all="$(printf '%s' "$TOOL_INPUT" | jq -r '.replace_all // false' 2>/dev/null || true)"

  if [[ -z "$old_string" ]]; then
    _fail_closed "edit_empty_old_string" \
      "the Edit carries an empty old_string; the resulting document cannot be reconstructed."
  fi

  if [[ ! -f "$file_path" || ! -r "$file_path" ]]; then
    _fail_closed "edit_target_unreadable" \
      "on-disk verdict map '${file_path}' is missing or unreadable; the Edit result cannot be reconstructed."
  fi

  current="$(cat "$file_path" 2>/dev/null || true)"

  if [[ "$current" != *"$old_string"* ]]; then
    _fail_closed "edit_old_string_not_found" \
      "old_string does not occur in '${file_path}'; the Edit result cannot be reconstructed."
  fi

  if [[ "$replace_all" == "true" ]]; then
    new_content="${current//"$old_string"/"$new_string"}"
  else
    new_content="${current/"$old_string"/"$new_string"}"
  fi
else
  new_content="$(printf '%s' "$TOOL_INPUT" | jq -r '.new_file // .content // ""' 2>/dev/null || true)"
fi

if [[ -z "$new_content" ]]; then
  _fail_closed "empty_extraction" \
    "no document content could be extracted from the ${TOOL_NAME:-Write} payload."
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

session_substance_dir="$(active_session_dir 2>/dev/null || true)"
repo_substance_root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"

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
  if _token_present_in_substance "$token" "$session_substance_dir" "$repo_substance_root"; then
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
