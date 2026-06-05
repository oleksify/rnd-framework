#!/usr/bin/env bash
# tests/premortem-skill.test.sh — Content-presence tests for skills/rnd-premortem/SKILL.md
# Usage: bash tests/premortem-skill.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

SKILL="${PLUGIN_ROOT}/skills/rnd-premortem/SKILL.md"
content="$(cat "$SKILL")"

# ---------------------------------------------------------------------------
# Frontmatter
# ---------------------------------------------------------------------------
printf '\n--- premortem skill: frontmatter ---\n'

assert_contains "frontmatter has name: rnd-premortem" \
  "name: rnd-premortem" "$content"

assert_contains "frontmatter has description field" \
  "description:" "$content"

assert_contains "frontmatter has effort: low" \
  "effort: low" "$content"

assert_contains "frontmatter has user-invocable: false" \
  "user-invocable: false" "$content"

# ---------------------------------------------------------------------------
# Five core framings
# ---------------------------------------------------------------------------
printf '\n--- premortem skill: five core framings ---\n'

assert_contains "framing: wrong external-service assumption" \
  "external-service" "$content"

assert_contains "framing: data-model misfit" \
  "data-model" "$content"

assert_contains "framing: performance at scale" \
  "performance at scale" "$content"

assert_contains "framing: auth/permission edge case" \
  "auth" "$content"

assert_contains "framing: user-meant-something-different" \
  "user-meant" "$content"

# ---------------------------------------------------------------------------
# Per-agent prompt template
# ---------------------------------------------------------------------------
printf '\n--- premortem skill: per-agent prompt template ---\n'

assert_contains "template section present" \
  "prompt" "$content"

assert_contains "template instructs imagining failure" \
  "narrative" "$content"

assert_contains "template prohibits file writes" \
  "no file" "$content"

assert_contains "template prohibits tool use" \
  "no tool" "$content"

# ---------------------------------------------------------------------------
# premortem.md format with FM<k> IDs
# ---------------------------------------------------------------------------
printf '\n--- premortem skill: premortem.md format ---\n'

assert_contains "references premortem.md artifact" \
  "premortem.md" "$content"

assert_contains "uses FM<k> notation" \
  "FM<k>" "$content"

assert_contains "uses FM1 as concrete example" \
  "FM1" "$content"

assert_contains "states orchestrator owns the file" \
  "orchestrator" "$content"

assert_contains "states premortem.md is immutable input" \
  "immutable" "$content"

# ---------------------------------------------------------------------------
# Emit invocation and bounds
# ---------------------------------------------------------------------------
printf '\n--- premortem skill: emit invocation and bounds ---\n'

assert_contains "emit script name present" \
  "premortem-emit.sh" "$content"

assert_contains "emit framings_csv argument present" \
  "framings_csv" "$content"

assert_contains "emit failure_mode_count argument present" \
  "failure_mode_count" "$content"

assert_contains "lower bound 3 stated" \
  "3" "$content"

assert_contains "upper bound 7 stated" \
  "7" "$content"

assert_contains "default N = 5 stated" \
  "5" "$content"

report
