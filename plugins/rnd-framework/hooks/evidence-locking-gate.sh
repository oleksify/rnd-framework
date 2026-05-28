#!/usr/bin/env bash
# hooks/evidence-locking-gate.sh — PreToolUse Write|Edit hook.
# Intercepts verifier writes of wave-N-verdict-map.json and validates the
# evidence array shape. Blocks writes where any assertion entry has an empty,
# missing, or trivial evidence array. Emits exactly one gate_fired audit event
# per blocked write (first offender only).
#
# Trivial-token denylist, minimum length threshold, and citation markers are
# sourced from lib/verdict-map-schema.json (the SSOT). Hardcoded fallback
# values are used only if the schema file is missing or unreadable.

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

if [[ -r "$VERDICT_MAP_SCHEMA_PATH" ]]; then
  TRIVIAL_TOKENS_JSON="$(jq -c '."x-trivial-tokens"' "$VERDICT_MAP_SCHEMA_PATH" 2>/dev/null || true)"
  MIN_EVIDENCE_LENGTH="$(jq -r '."x-min-evidence-length"' "$VERDICT_MAP_SCHEMA_PATH" 2>/dev/null || true)"
  CITATION_MARKERS_JSON="$(jq -c '."x-evidence-citation-markers"' "$VERDICT_MAP_SCHEMA_PATH" 2>/dev/null || true)"
fi

# Hardcoded fallbacks (kept aligned with the schema).
[[ -n "$TRIVIAL_TOKENS_JSON" && "$TRIVIAL_TOKENS_JSON" != "null" ]] || \
  TRIVIAL_TOKENS_JSON='["","n/a","na","none","ok","passed","fail","true","false","yes","no","done","ran tests","compiles","no errors","looks good","lgtm","tbd","todo"]'
[[ -n "$MIN_EVIDENCE_LENGTH" && "$MIN_EVIDENCE_LENGTH" != "null" ]] || \
  MIN_EVIDENCE_LENGTH="40"
[[ -n "$CITATION_MARKERS_JSON" && "$CITATION_MARKERS_JSON" != "null" ]] || \
  CITATION_MARKERS_JSON='[":","\/","`","\"","<"]'

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

if [[ -z "$offender" ]]; then
  exit 0
fi

offender_id="${offender%%$'\t'*}"
violation_tag="${offender##*$'\t'}"

# Emit exactly one audit event for the first offender.
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
