#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

COVERAGE_SCRIPT="${PLUGIN_ROOT}/lib/audit-remediation-coverage.sh"

printf '\n--- coverage-script-exists-and-runs ---\n'

coverage_output=''
coverage_exit=0
coverage_output="$(bash "$COVERAGE_SCRIPT" 2>&1)" || coverage_exit=$?

assert_eq \
  "audit remediation coverage script exits 0" \
  "0" \
  "$coverage_exit"

required_classes=(
  'hook-path-overmatch'
  'destructive-git-bypass'
  'post-review-quality-debt'
  'per-shape-session-join'
  'backfill-session-id-fallback'
  'sycophancy-head-fallback'
  'verifier-prose-report-contract'
  'validate-xrefs-negative-coverage'
  'validate-sh-negative-coverage'
  'command-and-docs-drift'
  'pipeline-artifact-session-docs'
)

for finding_class in "${required_classes[@]}"; do
  assert_contains \
    "coverage output includes ${finding_class}" \
    "$finding_class" \
    "$coverage_output"
done

assert_eq \
  "coverage output reports only ok rows" \
  "pass" \
  "$(printf '%s\n' "$coverage_output" | grep -q '^OK|' && printf pass || printf fail)"

report
