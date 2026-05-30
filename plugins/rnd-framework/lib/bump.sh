#!/usr/bin/env bash
# bump.sh — Increment version, prepend CHANGELOG entry, stage files.
#
# Usage:
#   bump.sh [--patch|--minor|--major] <headline> [description]
#
# Flags:
#   --patch   Increment patch (X.Y.Z → X.Y.Z+1) — default
#   --minor   Increment minor (X.Y.Z → X.Y+1.0)
#   --major   Increment major (X.Y.Z → X+1.0.0)
#
# Arguments:
#   headline     Required. Short title for the CHANGELOG entry.
#   description  Optional. Body paragraph for the CHANGELOG entry.
#
# Effect:
#   1. Reads current version from plugin.json via jq
#   2. Increments version based on flag (default: patch)
#   3. Writes new version back to plugin.json atomically
#   4. Prepends new CHANGELOG entry to CHANGELOG.md
#   5. Stages plugin.json and CHANGELOG.md via git add

set -euo pipefail

# When invoked from the cache (${CLAUDE_PLUGIN_ROOT}), dirname resolves to
# the cache — not a git repo.  Prefer the git working tree root if available,
# falling back to the script's own location for direct invocation.
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if git rev-parse --show-toplevel &>/dev/null; then
  GIT_ROOT="$(git rev-parse --show-toplevel)"
  # Find the plugin dir inside the repo (look for .claude-plugin/plugin.json)
  for candidate in "$GIT_ROOT" "$GIT_ROOT/plugins/rnd-framework"; do
    if [ -f "$candidate/.claude-plugin/plugin.json" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
  PLUGIN_DIR="${PLUGIN_DIR:-$SCRIPT_DIR}"
else
  PLUGIN_DIR="$SCRIPT_DIR"
fi
PLUGIN_JSON="$PLUGIN_DIR/.claude-plugin/plugin.json"
CHANGELOG="$PLUGIN_DIR/CHANGELOG.md"

# --- Validate dependencies ---
if ! command -v jq &>/dev/null; then
  echo "error: jq is required but not found in PATH" >&2
  exit 1
fi

# --- Parse version type flag ---
BUMP_TYPE="patch"
case "${1:-}" in
  --patch) BUMP_TYPE="patch"; shift ;;
  --minor) BUMP_TYPE="minor"; shift ;;
  --major) BUMP_TYPE="major"; shift ;;
esac

# --- Validate arguments ---
if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: bump.sh [--patch|--minor|--major] <headline> [description]" >&2
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
if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: current version '${CURRENT_VERSION}' is not valid semver (expected X.Y.Z)" >&2
  exit 1
fi
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# ZeroVer guard: while the major is 0 the project is experimental by design.
# Advancing to 1.0.0 is an out-of-band decision, not a routine bump.
if [[ "$BUMP_TYPE" == "major" && "$MAJOR" == "0" ]]; then
  echo "error: refusing --major: project is 0.x under ZeroVer (0ver.org) — this is an experimental R&D framework; advancing to 1.0.0 requires an explicit out-of-band decision, not a routine bump" >&2
  exit 1
fi

case "$BUMP_TYPE" in
  major) NEW_VERSION="$(( MAJOR + 1 )).0.0" ;;
  minor) NEW_VERSION="${MAJOR}.$(( MINOR + 1 )).0" ;;
  patch) NEW_VERSION="${MAJOR}.${MINOR}.$(( PATCH + 1 ))" ;;
esac

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
first_line="$(head -1 "$CHANGELOG")"
if ! printf '%s\n' "$first_line" | grep -q "^# "; then
  printf 'error: CHANGELOG first line is not an H1 header (expected "# ..."), got: %s\n' "$first_line" >&2
  exit 1
fi
HEADER="$first_line"
REST="$(tail -n +2 "$CHANGELOG")"
printf '%s\n\n%s%s' "$HEADER" "$NEW_ENTRY" "$REST" > "$CHANGELOG"

# --- Stage files ---
git -C "$PLUGIN_DIR" add "$PLUGIN_JSON" "$CHANGELOG"

# --- Auto-tag via claude plugin tag (non-fatal) ---
# `claude plugin tag` (v2.1.118+) reads the version from plugin.json and
# creates a git tag for the plugin release.  This is best-effort: if claude
# is not in PATH, or the tag already exists, we warn and continue — the bump
# itself has already succeeded and is fully recoverable without the tag.
if command -v claude &>/dev/null; then
  if ! claude plugin tag "$PLUGIN_DIR" 2>&1; then
    echo "warning: 'claude plugin tag' failed — tag the release manually if needed" >&2
  fi
else
  echo "warning: claude not in PATH; skipping plugin tag — run 'claude plugin tag' manually after committing" >&2
fi

echo "Bumped version $CURRENT_VERSION → $NEW_VERSION"
