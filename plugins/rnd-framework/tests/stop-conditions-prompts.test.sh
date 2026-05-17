#!/usr/bin/env bash
# Tests: Stop Conditions section and Heuristic ceiling field are present in the
# orchestration skill and planner agent prompts.
# Usage: bash tests/stop-conditions-prompts.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

ORCHESTRATION="${SCRIPT_DIR}/../skills/rnd-orchestration/SKILL.md"
PLANNER="${SCRIPT_DIR}/../agents/rnd-planner.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

grep_file() {
  grep -qE "$1" "$2"
}

assert_grep() {
  local desc="$1" pattern="$2" file="$3"
  assert_eq "$desc" "pass" "$(grep_file "$pattern" "$file" && printf pass || printf fail)"
}

# ---------------------------------------------------------------------------
# Orchestration skill — Stop Conditions section
# ---------------------------------------------------------------------------

printf '%s\n' '--- orchestration skill: Stop Conditions section ---'

assert_grep \
  "orchestration skill: ## Stop Conditions heading" \
  "^## Stop Conditions" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: names RND_STOP_VERDICT_FLIPS" \
  "RND_STOP_VERDICT_FLIPS" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: names verdict_history subcommand" \
  "verdict_history" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: names RND_STOP_PLAN_RATIO" \
  "RND_STOP_PLAN_RATIO" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: names Heuristic ceiling field" \
  "Heuristic ceiling" \
  "$ORCHESTRATION"

# ---------------------------------------------------------------------------
# Orchestration skill — AskUserQuestion examples for both halt types
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- orchestration skill: AskUserQuestion examples ---'

assert_grep \
  "orchestration skill: AskUserQuestion present in Stop Conditions" \
  "AskUserQuestion" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: verdict flip halt option present" \
  "verdict.flip|verdict_flip|flip" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: plan oversized halt option present" \
  "plan.size|plan_size|oversized|ceiling" \
  "$ORCHESTRATION"

# ---------------------------------------------------------------------------
# Orchestration skill — gateFired record on halt
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- orchestration skill: gateFired record on halt ---'

assert_grep \
  "orchestration skill: stop_condition_verdict_flip gate name" \
  "stop_condition_verdict_flip" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: stop_condition_plan_size gate name" \
  "stop_condition_plan_size" \
  "$ORCHESTRATION"

assert_grep \
  "orchestration skill: gateFired documented in Stop Conditions" \
  "gateFired" \
  "$ORCHESTRATION"

# ---------------------------------------------------------------------------
# Planner agent — Heuristic ceiling requirement
# ---------------------------------------------------------------------------

printf '\n%s\n' '--- planner agent: Heuristic ceiling ---'

assert_grep \
  "planner agent: Heuristic ceiling field required" \
  "Heuristic ceiling" \
  "$PLANNER"

# ---------------------------------------------------------------------------
report
