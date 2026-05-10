#!/usr/bin/env bash
# PreToolUse hook for Read: validates evidence-pack manifest.json for
# disallowed free-text fields before allowing a Verifier-side read.
#
# Responsibilities:
#   1. Information barrier — blocks reads of self-assessment and /briefs/ paths.
#   2. Manifest schema gate — when a verifier reads evidence/T*/manifest.json,
#      validate that the file contains no disallowed free-text fields.
#   3. Auto-allow for all other paths (no opinion).

# shellcheck source=./lib.sh
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HOOK_DIR}/lib.sh"

# Disallowed fields are sourced from the manifest schema's `x-disallowed-fields`
# extension so the schema file is the single source of truth. Hard-coded
# fallback list is used only if the schema file is missing or unreadable.
readonly MANIFEST_SCHEMA_PATH="${HOOK_DIR}/../lib/manifest-schema.json"

_load_disallowed_fields() {
  if [[ -r "$MANIFEST_SCHEMA_PATH" ]]; then
    jq -r '."x-disallowed-fields"[]?' "$MANIFEST_SCHEMA_PATH" 2>/dev/null
  fi
}

DISALLOWED_FIELDS=()
while IFS= read -r field; do
  [[ -n "$field" ]] && DISALLOWED_FIELDS+=("$field")
done < <(_load_disallowed_fields)

# Fallback hard-coded list (kept aligned with the schema).
if [[ ${#DISALLOWED_FIELDS[@]} -eq 0 ]]; then
  DISALLOWED_FIELDS=(notes summary confidence reasoning explanation)
fi
readonly DISALLOWED_FIELDS

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Returns 0 if path matches the evidence-pack manifest pattern:
#   <rnd_dir>/evidence/T<id>/manifest.json
# Checks .rnd/ prefix first via is_plugin_artifact_path, then the path structure.
_is_manifest_path() {
  local path="$1"

  is_plugin_artifact_path "$path" || return 1

  [[ "$path" == */evidence/T*/manifest.json ]]
}

# Returns 0 (valid) if the file at <path> contains none of the disallowed fields.
# Returns 1 (invalid) and prints the first offending field name to stdout if one is found.
_validate_manifest() {
  local path="$1"

  local content
  content="$(jq -c '.' "$path" 2>/dev/null)" || {
    printf 'unparseable'
    return 1
  }

  local field
  for field in "${DISALLOWED_FIELDS[@]}"; do
    if printf '%s' "$content" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
      printf '%s' "$field"
      return 1
    fi
  done

  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

parse_input
file_path="$(extract_file_path "$TOOL_INPUT")"

# 1. Information barrier — must run first to preserve existing semantics.
if is_barrier_violation "$file_path" "${AGENT_TYPE}"; then
  block_msg "INFORMATION BARRIER: self-assessment files and briefs/ artifacts are records written for the orchestrator and the user — not for the Verifier. Direct reading is blocked to maintain information barriers between Builder and Verifier."
fi

# 2. Manifest schema gate — only applies when a verifier reads a manifest path.
agent_lower="$(_lower "${AGENT_TYPE}")"

if _is_manifest_path "$file_path" && [[ "$agent_lower" == *"verifier"* ]]; then
  offending_field="$(_validate_manifest "$file_path")" || {
    block_msg "EVIDENCE PACK BARRIER: manifest.json at '${file_path}' contains disallowed field '${offending_field}'. Evidence packs must not include free-text reasoning fields (notes, summary, confidence, reasoning, explanation). Rebuild the evidence pack without those fields."
  }

  allow_json
  exit 0
fi

# 3. No opinion — exit 0 with no stdout.
exit 0
