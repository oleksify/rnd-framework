#!/usr/bin/env bash
# tests/calibration-schema-additions.test.sh — Smoke tests for schema field additions
# in skills/rnd-calibration/SKILL.md and related skill files.
# Usage: bash tests/calibration-schema-additions.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

CALIB_SKILL="${PLUGIN_ROOT}/skills/rnd-calibration/SKILL.md"
MULTI_JUDGE_SKILL="${PLUGIN_ROOT}/skills/rnd-multi-judge/SKILL.md"
ORCH_SKILL="${PLUGIN_ROOT}/skills/rnd-orchestration/SKILL.md"

printf '\n--- calibration schema: multiJudge field ---\n'

multi_judge_content="$(cat "$CALIB_SKILL")"

assert_contains "SKILL.md documents multiJudge field" \
  "multiJudge" "$multi_judge_content"

assert_contains "multiJudge has judgeA field" \
  "judgeA" "$multi_judge_content"

assert_contains "multiJudge has judgeB field" \
  "judgeB" "$multi_judge_content"

assert_contains "multiJudge has agreed field" \
  "agreed" "$multi_judge_content"

assert_contains "multiJudge has resolution field" \
  "resolution" "$multi_judge_content"

assert_contains "multiJudge has tiebreaker field" \
  "tiebreaker" "$multi_judge_content"

printf '\n--- calibration schema: task_type field ---\n'

assert_contains "SKILL.md documents task_type field" \
  "task_type" "$multi_judge_content"

assert_contains "task_type includes refactor" \
  "refactor" "$multi_judge_content"

assert_contains "task_type includes new-feature" \
  "new-feature" "$multi_judge_content"

assert_contains "task_type includes bugfix" \
  "bugfix" "$multi_judge_content"

assert_contains "task_type includes docs" \
  "docs" "$multi_judge_content"

assert_contains "task_type includes config" \
  "config" "$multi_judge_content"

assert_contains "task_type includes infra" \
  "infra" "$multi_judge_content"

printf '\n--- calibration schema: gateFired field ---\n'

assert_contains "SKILL.md documents gateFired field" \
  "gateFired" "$multi_judge_content"

assert_contains "gateFired has gate field" \
  "gate" "$multi_judge_content"

assert_contains "gateFired has outcome field" \
  "outcome" "$multi_judge_content"

assert_contains "gateFired has task_id sub-field" \
  "task_id" "$multi_judge_content"

assert_contains "gateFired lists existence_prepass producer" \
  "existence_prepass" "$multi_judge_content"

assert_contains "gateFired lists stop_condition_revisions producer" \
  "stop_condition_revisions" "$multi_judge_content"

assert_contains "gateFired lists coverage_gaps_gate producer" \
  "coverage_gaps_gate" "$multi_judge_content"

assert_contains "gateFired lists assumption_unchecked producer" \
  "assumption_unchecked" "$multi_judge_content"

printf '\n--- rnd-multi-judge: Step 5 calibration write (multiJudge) ---\n'

multi_judge_file="$(cat "$MULTI_JUDGE_SKILL")"

assert_contains "rnd-multi-judge Step 5 has multiJudge calibration write" \
  "multiJudge" "$multi_judge_file"

printf '\n--- rnd-orchestration: task_type inference policy ---\n'

orch_content="$(cat "$ORCH_SKILL")"

assert_contains "rnd-orchestration has task_type Inference Policy section" \
  "task_type Inference Policy" "$orch_content"

assert_contains "task_type inference has refactor keyword" \
  "refactor" "$orch_content"

assert_contains "task_type inference has feature keyword" \
  "feature" "$orch_content"

assert_contains "task_type inference has bugfix keyword" \
  "bugfix" "$orch_content"

assert_contains "task_type inference defaults to infra" \
  "infra" "$orch_content"

report
