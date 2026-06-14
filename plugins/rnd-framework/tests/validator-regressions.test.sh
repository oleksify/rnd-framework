#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

VALIDATE_SH="${PLUGIN_ROOT}/lib/validate.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

copy_plugin() {
  local name="$1"
  local plugin_copy="${TMP_DIR}/${name}"

  cp -R "$PLUGIN_ROOT" "$plugin_copy"

  printf '%s\n' "$plugin_copy"
}

run_validate() {
  local plugin_copy="$1"

  set +e
  VALIDATE_OUTPUT="$(bash "$plugin_copy/lib/validate.sh" 2>&1)"
  VALIDATE_STATUS=$?
  set -e
}

run_sourced_xrefs() {
  local plugin_copy="$1"

  set +e
  XREFS_OUTPUT="$(PLUGIN_ROOT="$plugin_copy" bash -c '
set -euo pipefail

FAIL_COUNT=0

record_pass() { :; }
record_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "FAIL:%s\n" "$1"
}
emit_info() { :; }
begin_category() { :; }
in_array() {
  local needle="$1"
  shift
  local item

  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

source "$PLUGIN_ROOT/lib/validate-xrefs.sh"
validate_cross_refs
printf "FAIL_COUNT=%s\n" "$FAIL_COUNT"
' 2>&1)"
  XREFS_STATUS=$?
  set -e
}

printf '\n--- sourced-xrefs-broken-agent-skill-reference ---\n'

XREFS_PLUGIN="$(copy_plugin xrefs-broken)"
perl -0pi -e 's/rnd-framework:rnd-building/rnd-framework:rnd-building-missing/' \
  "$XREFS_PLUGIN/agents/rnd-builder.md"

run_sourced_xrefs "$XREFS_PLUGIN"

assert_eq \
  "sourced xrefs returns through the caller shell" \
  "0" \
  "$XREFS_STATUS"

assert_contains \
  "sourced xrefs records the broken reference through record_fail" \
  "agent 'rnd-builder' skill ref 'rnd-framework:rnd-building-missing' — skill 'rnd-building-missing' not found" \
  "$XREFS_OUTPUT"

assert_contains \
  "sourced xrefs increments the failure counter" \
  "FAIL_COUNT=1" \
  "$XREFS_OUTPUT"

printf '\n--- validate-sh-missing-plugin-json ---\n'

MISSING_PLUGIN_JSON="$(copy_plugin missing-plugin-json)"
rm "$MISSING_PLUGIN_JSON/.claude-plugin/plugin.json"

run_validate "$MISSING_PLUGIN_JSON"

assert_eq \
  "missing plugin.json exits non-zero" \
  "1" \
  "$VALIDATE_STATUS"

assert_contains \
  "missing plugin.json reports the missing manifest" \
  "plugin.json not found" \
  "$VALIDATE_OUTPUT"

printf '\n--- validate-sh-missing-plugin-version ---\n'

MISSING_PLUGIN_VERSION="$(copy_plugin missing-plugin-version)"
printf '{"name":"rnd-framework","description":"broken"}\n' > "$MISSING_PLUGIN_VERSION/.claude-plugin/plugin.json"

run_validate "$MISSING_PLUGIN_VERSION"

assert_eq \
  "plugin.json without version exits non-zero" \
  "1" \
  "$VALIDATE_STATUS"

assert_contains \
  "plugin.json without version reports the missing version field" \
  "plugin.json missing 'version'" \
  "$VALIDATE_OUTPUT"

printf '\n--- validate-sh-healthy-plugin ---\n'

run_validate "$PLUGIN_ROOT"

assert_eq \
  "healthy plugin exits 0" \
  "0" \
  "$VALIDATE_STATUS"

report
