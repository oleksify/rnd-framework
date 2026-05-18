#!/usr/bin/env bash
# cross-phrasing-check.sh — ADVISORY paraphrase-stability check for pre-reg Correctness criteria.
#
# ADVISORY: callable lib only. No agent currently dispatches it.
#
# Usage:  cross-phrasing-check.sh <pre-reg-path>
#         cross-phrasing-check.sh --help
#
# Output: JSON with 5 keys:
#   original_criteria_count, paraphrased_criteria_count,
#   structurally_equivalent, drift_score, drifted_items
#
# Paraphrase rules (prose-only; backtick content preserved):
#   returns 0 / succeeds / exit code is 0 / successful exit → exits 0
#   grep X → search for X
#   wc -l  → count lines
#   find   → locate  (word boundary)
#   file exists at → is present at
#   at least N results → returns ≥ N

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_usage() {
  printf 'Usage: cross-phrasing-check.sh <pre-reg-path>\n\n'
  printf 'ADVISORY: paraphrase-stability check for pre-reg Correctness criteria.\n'
  printf 'No agent currently dispatches this helper — future verifier/multi-judge work may wire it in.\n\n'
  printf 'Output JSON (5 keys): original_criteria_count, paraphrased_criteria_count,\n'
  printf '  structurally_equivalent, drift_score, drifted_items\n'
}

if [[ "${1:-}" == "--help" ]]; then _usage; exit 0; fi
if [[ $# -lt 1 ]]; then printf 'Error: pre-reg path required\n' >&2; _usage >&2; exit 1; fi

_PREREG="$1"
[[ -f "$_PREREG" ]] || { printf 'Error: file not found: %s\n' "$_PREREG" >&2; exit 1; }

_CLASSIFY="${_SCRIPT_DIR}/criteria-classify.sh"
[[ -x "$_CLASSIFY" ]] || { printf 'Error: criteria-classify.sh not found\n' >&2; exit 1; }

# ---------------------------------------------------------------------------
# Single awk pass: extract criteria, paraphrase, classify each item, emit JSON.
# Output: one JSON line per item:
#   {"orig":"...","para":"...","orig_mech":0|1,"para_mech":0|1}
# ---------------------------------------------------------------------------
_ITEM_DATA="$(awk '
  BEGIN { in_c = 0; n = 0 }

  /^##[[:space:]]+(Correctness)[[:space:]]*:?[[:space:]]*$/ { in_c = 1; next }
  /^[[:space:]]+Correctness:[[:space:]]*$/                   { in_c = 1; next }
  in_c && /^##[[:space:]]/                                   { in_c = 0; next }
  in_c && /^[[:space:]]+[A-Z][a-zA-Z ]*:[[:space:]]*$/      { in_c = 0; next }

  in_c && /^[[:space:]]*-[[:space:]]\[ \]/ {
    orig = $0; para = paraphrase(orig)
    n++; origs[n] = orig; paras[n] = para
    orig_mechs[n] = classify(tolower(orig))
    para_mechs[n] = classify(tolower(para))
  }

  END {
    for (i = 1; i <= n; i++) {
      oe = origs[i]; gsub(/"/, "\\\"", oe)
      pe = paras[i];  gsub(/"/, "\\\"", pe)
      printf "{\"orig\":\"%s\",\"para\":\"%s\",\"orig_mech\":%d,\"para_mech\":%d}\n", \
        oe, pe, orig_mechs[i], para_mechs[i]
    }
  }

  function paraphrase(line,    res, bt, bt2, prose, code) {
    res = ""
    while (length(line) > 0) {
      bt = index(line, "`")
      if (bt == 0) { res = res sub_prose(line); break }
      prose = substr(line, 1, bt - 1); res = res sub_prose(prose); line = substr(line, bt)
      bt2 = index(substr(line, 2), "`")
      if (bt2 == 0) { res = res line; break }
      code = substr(line, 1, bt2 + 1); res = res code; line = substr(line, bt2 + 2)
    }
    return res
  }

  function sub_prose(s,    t) {
    t = s
    gsub(/[Ss]uccessful exit/, "exits 0", t)
    gsub(/exit code is 0/, "exits 0", t)
    gsub(/returns 0/, "exits 0", t)
    gsub(/succeeds([^a-zA-Z]|$)/, "exits 0 ", t)
    gsub(/at least ([0-9]+) results/, "returns \342\211\245 \\1", t)
    gsub(/grep /, "search for ", t)
    gsub(/wc -l/, "count lines", t)
    gsub(/(^|[[:space:]])find([[:space:]]|$)/, " locate ", t)
    gsub(/file exists at/, "is present at", t)
    return t
  }

  function classify(item,    m) {
    m = 0
    if (index(item, "grep")        > 0) m = 1
    if (index(item, "jq ")        > 0) m = 1
    if (item ~ /[^a-z]jq$/ || item ~ /[^a-z]jq[^a-z]/) m = 1
    if (index(item, "exit code")   > 0) m = 1
    if (index(item, "exits 0")     > 0) m = 1
    if (index(item, "file exists") > 0) m = 1
    if (index(item, "wc -l")       > 0) m = 1
    if (index(item, "find ")       > 0) m = 1
    if (index(item, "returns")     > 0 && \
        (index(item, "\342\211\245") > 0 || index(item, ">=") > 0 || index(item, "at least") > 0)) m = 1
    if (item ~ /bash.*\.test\.sh.*exits/) m = 1
    if (item ~ /\.test\.sh.*exits[ ]*0/)  m = 1
    return m
  }
' "$_PREREG")"

if [[ -z "$_ITEM_DATA" ]]; then
  printf '{"original_criteria_count":0,"paraphrased_criteria_count":0,"structurally_equivalent":true,"drift_score":0,"drifted_items":[]}\n'
  exit 0
fi

_ORIG_COUNT="$(printf '%s\n' "$_ITEM_DATA" | grep -c .)"

# Compute per-item drift
_DRIFTED=0; _DRIFT_JSON="["; _FIRST=1
while IFS= read -r _row; do
  _om="$(printf '%s' "$_row" | awk -F'"orig_mech":' '{print $2}' | cut -d',' -f1)"
  _pm="$(printf '%s' "$_row" | awk -F'"para_mech":' '{print $2}' | tr -d '}')"
  if [[ "$_om" != "$_pm" ]]; then
    _DRIFTED=$(( _DRIFTED + 1 ))
    [[ "$_FIRST" -eq 0 ]] && _DRIFT_JSON="${_DRIFT_JSON},"
    _ov="$(printf '%s' "$_row" | awk -F'"orig":"' '{print $2}' | awk -F'","para"' '{print $1}')"
    _pv="$(printf '%s' "$_row" | awk -F'"para":"' '{print $2}' | awk -F'","orig_mech"' '{print $1}')"
    _DRIFT_JSON="${_DRIFT_JSON}{\"original\":\"${_ov}\",\"paraphrased\":\"${_pv}\"}"
    _FIRST=0
  fi
done <<< "$_ITEM_DATA"
_DRIFT_JSON="${_DRIFT_JSON}]"

# Build hash-sorted paraphrased pre-reg for overall level comparison
_PARA_LINES="$(printf '%s\n' "$_ITEM_DATA" | awk -F'"para":"' '{print $2}' | awk -F'","orig_mech"' '{print $1}')"
_PARA_SORTED="$(printf '%s\n' "$_PARA_LINES" | awk '{cmd="printf \"%s\" " "\047" $0 "\047" " | md5sum | cut -d\" \" -f1"; cmd|getline h; close(cmd); print h "  " $0}' | sort | cut -d' ' -f3-)"
_PARA_COUNT="$(printf '%s\n' "$_PARA_SORTED" | grep -c .)"

if [[ -z "${RND_DIR:-}" ]]; then
  printf 'Error: RND_DIR must be set\n' >&2
  exit 1
fi
_PARA_PREREG="${RND_DIR}/cross-phrasing-para-$$.md"
trap 'rm -f "$_PARA_PREREG"' EXIT
{ printf '## Correctness\n\n'; printf '%s\n' "$_PARA_SORTED"; printf '\n## Quality\n'; } > "$_PARA_PREREG"

_ORIG_LEVEL="$(bash "$_CLASSIFY" "$_PREREG"      | awk -F'"recommended_level":"' '{if(NF>1) print $2}' | tr -d '"}')"
_PARA_LEVEL="$(bash "$_CLASSIFY" "$_PARA_PREREG" | awk -F'"recommended_level":"' '{if(NF>1) print $2}' | tr -d '"}')"

_STRUCT_EQ="false"
[[ "$_ORIG_COUNT" -eq "$_PARA_COUNT" && "$_ORIG_LEVEL" == "$_PARA_LEVEL" ]] && _STRUCT_EQ="true"

_SCORE="0"
[[ "$_ORIG_COUNT" -gt 0 && "$_DRIFTED" -gt 0 ]] && \
  _SCORE="$(awk "BEGIN { printf \"%.4g\", ${_DRIFTED}/${_ORIG_COUNT} }")"

printf '{"original_criteria_count":%d,"paraphrased_criteria_count":%d,"structurally_equivalent":%s,"drift_score":%s,"drifted_items":%s}\n' \
  "$_ORIG_COUNT" "$_PARA_COUNT" "$_STRUCT_EQ" "$_SCORE" "$_DRIFT_JSON"
