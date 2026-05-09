#!/usr/bin/env bash
# tight-dir.sh — Compute the tight-loop plugin artifact directory path.
#
# Usage:
#   tight-dir.sh        Print the project base dir (creates nothing)
#   tight-dir.sh -c     Create the base directory and print its path
#   tight-dir.sh --base Alias for bare invocation; print the project base dir
#
# Base path: <claude-config-dir>/.tight-loop/<project-slug>/
#
# Unlike rnd-dir.sh, this script has no session nesting — it outputs the
# project base directory directly. There is no --finish, --roadmap, or --facts
# flag because tight-loop does not use sessions.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=plugin-dir-base.sh
source "${_SCRIPT_DIR}/plugin-dir-base.sh" ".tight-loop" "${1:-}"

[[ "$FLAG" = "--base" ]] && { printf '%s\n' "$BASE_DIR"; exit 0; }
[[ "$FLAG" = "-c"     ]] && { mkdir -p "$BASE_DIR"; printf '%s\n' "$BASE_DIR"; exit 0; }

printf '%s\n' "$BASE_DIR"
