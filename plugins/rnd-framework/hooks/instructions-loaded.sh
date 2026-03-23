#!/usr/bin/env bash
# hooks/instructions-loaded.sh — Reminds orchestrator to extract project coding rules.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
advisory_json "Run /rnd-framework:rnd-standards to extract project coding rules before planning."
exit 0
