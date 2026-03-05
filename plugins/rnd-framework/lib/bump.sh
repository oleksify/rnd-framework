#!/usr/bin/env bash
# bump.sh — Increment patch version, prepend CHANGELOG entry, stage files.
#
# Usage:
#   bump.sh <headline> [description]
#
# Arguments:
#   headline     Required. Short title for the CHANGELOG entry.
#   description  Optional. Body paragraph for the CHANGELOG entry.
#
# Effect:
#   1. Reads current version from plugin.json via jq
#   2. Increments patch number (e.g., 0.7.24 → 0.7.25)
#   3. Writes new version back to plugin.json atomically
#   4. Prepends new CHANGELOG entry to CHANGELOG.md
#   5. Stages plugin.json and CHANGELOG.md via git add

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
CHANGELOG="$PLUGIN_DIR/CHANGELOG.md"

# --- Validate dependencies ---
if ! command -v jq &>/dev/null; then
  echo "error: jq is required but not found in PATH" >&2
  exit 1
fi

# --- Validate arguments ---
if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: bump.sh <headline> [description]" >&2
  exit 1
fi

HEADLINE="$1"
DESCRIPTION="${2:-}"

# --- Check CHANGELOG exists before modifying any files ---
if [ ! -f "$CHANGELOG" ]; then
  echo "error: CHANGELOG.md not found at ${CHANGELOG}" >&2
  exit 1
fi

# --- Read and increment version ---
CURRENT_VERSION="$(jq -r '.version' "$PLUGIN_JSON")"
if ! echo "$CURRENT_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: current version '${CURRENT_VERSION}' is not valid semver (expected X.Y.Z)" >&2
  exit 1
fi
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
NEW_PATCH=$(( PATCH + 1 ))
NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"

# --- Write new version atomically ---
TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT
jq --arg v "$NEW_VERSION" '.version = $v' "$PLUGIN_JSON" > "$TMP_JSON"
mv "$TMP_JSON" "$PLUGIN_JSON"

# --- Build CHANGELOG entry ---
TODAY="$(date +%Y-%m-%d)"
if [[ -n "$DESCRIPTION" ]]; then
  NEW_ENTRY="## ${NEW_VERSION} — ${TODAY}

### ${HEADLINE}

${DESCRIPTION}
"
else
  NEW_ENTRY="## ${NEW_VERSION} — ${TODAY}

### ${HEADLINE}
"
fi

# --- Prepend entry after first line (# Changelog header) ---
HEADER="$(head -1 "$CHANGELOG")"
REST="$(tail -n +2 "$CHANGELOG")"
printf '%s\n\n%s%s' "$HEADER" "$NEW_ENTRY" "$REST" > "$CHANGELOG"

# --- Stage files ---
git -C "$PLUGIN_DIR" add "$PLUGIN_JSON" "$CHANGELOG"

echo "Bumped version $CURRENT_VERSION → $NEW_VERSION"
