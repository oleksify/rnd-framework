#!/usr/bin/env bash
# rnd-dir.sh — Compute the RND artifacts directory path.
#
# Usage:
#   rnd-dir.sh          Print session path if .current-session exists, else base dir
#   rnd-dir.sh -c       Create directory structure; generate session ID if needed; print session path
#   rnd-dir.sh --finish Delete .current-session (idempotent); exit 0
#   rnd-dir.sh --base   Print just the project base dir; never creates directories
#   rnd-dir.sh --roadmap Print <base-dir>/roadmap.md; never creates directories
#
# Session path: <base>/sessions/<YYYYMMDD-HHMMSS-XXXX>/
# Base path:    <claude-config-dir>/.rnd/<project-slug>/

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../../lib/plugin-dir-base.sh
source "${_SCRIPT_DIR}/../../../lib/plugin-dir-base.sh" ".rnd" "${1:-}"

[[ "$FLAG" = "--base"    ]] && { echo "$BASE_DIR";              exit 0; }
[[ "$FLAG" = "--roadmap" ]] && { echo "${BASE_DIR}/roadmap.md"; exit 0; }
[[ "$FLAG" = "--finish"  ]] && { rm -f "$SESSION_FILE";         exit 0; }
[[ "$FLAG" = "-c"        ]] && { _plugin_dir_create_session builds verifications integration; exit 0; }

_plugin_dir_current_or_base
