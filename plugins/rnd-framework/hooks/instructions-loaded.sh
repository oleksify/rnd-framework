#!/usr/bin/env bash
# hooks/instructions-loaded.sh — Reminds orchestrator to extract project coding rules.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
advisory_json "Read CLAUDE.md for project coding rules and consult the rnd-framework:kiss-practices skill before planning."
exit 0
