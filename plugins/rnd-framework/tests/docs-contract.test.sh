#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_ROOT}/../.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

assert_not_contains() {
  local desc="$1"
  local needle="$2"
  local haystack="$3"

  TESTS_TOTAL=$((TESTS_TOTAL + 1))

  if [[ "$haystack" == *"$needle"* ]]; then
    printf '  FAIL  %s\n' "$desc"
    printf '        did not expect to contain: %s\n' "$needle"
    printf '        actual: %s\n' "$haystack"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  else
    printf '  PASS  %s\n' "$desc"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  fi
}

sorted_command_inventory() {
  find "$PLUGIN_ROOT/commands" -maxdepth 1 -type f -name '*.md' -print \
    | sed 's#.*/##' \
    | sed 's/\.md$//' \
    | sort
}

readme_command_inventory() {
  grep '^| `/rnd-framework:' "$PLUGIN_ROOT/README.md" \
    | grep -o '/rnd-framework:[^` ]*' \
    | sed 's#/rnd-framework:##' \
    | sort
}

claude_command_inventory() {
  grep -o '/rnd-framework:[a-z0-9-]*' "$REPO_ROOT/CLAUDE.md" \
    | sed 's#/rnd-framework:##' \
    | sed '/^$/d' \
    | sort -u
}

assert_file_contains_text() {
  local desc="$1"
  local file="$2"
  local text="$3"
  local content

  content="$(<"$file")"

  assert_contains "$desc" "$text" "$content"
}

assert_file_not_contains_text() {
  local desc="$1"
  local file="$2"
  local text="$3"
  local content

  content="$(<"$file")"

  assert_not_contains "$desc" "$text" "$content"
}

EXPECTED_COMMANDS="$(sorted_command_inventory)"
README_COMMANDS="$(readme_command_inventory)"
CLAUDE_COMMANDS="$(claude_command_inventory)"
CURRENT_PIPELINE='Scope → Plan → Schedule → Build → [Reality Audit] → Verify → [Iterate] → Cleanup → Polish → Integrate → [Post-Review]'
CANONICAL_MANIFEST='M<NN>-T<NN>-<uuid>-manifest.md'
AUDIT_COMMAND="$PLUGIN_ROOT/commands/rnd-audit.md"
REVIEW_COMMAND="$PLUGIN_ROOT/commands/rnd-review.md"
STATS_COMMAND="$PLUGIN_ROOT/commands/rnd-stats.md"
HOOK_LIB="$PLUGIN_ROOT/hooks/lib.sh"
POST_REVIEW_WRITER="$PLUGIN_ROOT/lib/post-review-writer.sh"
SITE_INTRO="$REPO_ROOT/site/docs/00-intro.md"

printf '\n--- command-inventory-parity ---\n'

assert_eq \
  'plugin README command inventory matches tracked command files' \
  "$EXPECTED_COMMANDS" \
  "$README_COMMANDS"

assert_eq \
  'root CLAUDE command inventory matches tracked command files' \
  "$EXPECTED_COMMANDS" \
  "$CLAUDE_COMMANDS"

printf '\n--- phase-model-docs ---\n'

assert_file_contains_text \
  'root README shows the current full pipeline' \
  "$REPO_ROOT/README.md" \
  "$CURRENT_PIPELINE"

assert_file_not_contains_text \
  'root README no longer uses the four-phase shortcut as the full pipeline' \
  "$REPO_ROOT/README.md" \
  'Plan → Build → Verify → Integrate'

assert_file_contains_text \
  'plugin README shows the current full pipeline' \
  "$PLUGIN_ROOT/README.md" \
  "$CURRENT_PIPELINE"

assert_file_contains_text \
  'plugin README includes the post-review phase in the pipeline summary' \
  "$PLUGIN_ROOT/README.md" \
  '[Post-Review]'

assert_file_contains_text \
  'rnd-start describes the Scope-Lock-first pipeline' \
  "$PLUGIN_ROOT/commands/rnd-start.md" \
  "$CURRENT_PIPELINE"

assert_file_contains_text \
  'rnd-roadmap describes the Scope-Lock-first pipeline' \
  "$PLUGIN_ROOT/commands/rnd-roadmap.md" \
  "$CURRENT_PIPELINE"

assert_file_contains_text \
  'roadmapping skill describes the Scope-Lock-first pipeline' \
  "$PLUGIN_ROOT/skills/rnd-roadmapping/SKILL.md" \
  "$CURRENT_PIPELINE"

assert_file_contains_text \
  'orchestration skill describes the Scope-Lock-first pipeline' \
  "$PLUGIN_ROOT/skills/rnd-orchestration/SKILL.md" \
  "$CURRENT_PIPELINE"

printf '\n--- artifact-and-session-docs ---\n'

assert_file_contains_text \
  'rnd-status uses the canonical manifest filename' \
  "$PLUGIN_ROOT/commands/rnd-status.md" \
  "$CANONICAL_MANIFEST"

assert_file_contains_text \
  'rnd-debug uses the canonical manifest filename' \
  "$PLUGIN_ROOT/commands/rnd-debug.md" \
  "$CANONICAL_MANIFEST"

assert_file_contains_text \
  'output styles use the canonical manifest filename' \
  "$PLUGIN_ROOT/output-styles/scientific.md" \
  "$CANONICAL_MANIFEST"

assert_file_contains_text \
  'bootstrap skill uses the canonical manifest filename' \
  "$PLUGIN_ROOT/skills/rnd-using-rnd-framework/SKILL.md" \
  "$CANONICAL_MANIFEST"

assert_file_contains_text \
  'builder skill completion message uses the canonical manifest filename' \
  "$PLUGIN_ROOT/skills/rnd-building/SKILL.md" \
  "$CANONICAL_MANIFEST"

assert_file_contains_text \
  'verification skill reads the canonical manifest filename' \
  "$PLUGIN_ROOT/skills/rnd-verification/SKILL.md" \
  "$CANONICAL_MANIFEST"

assert_file_contains_text \
  'reality-auditing skill reads the canonical manifest filename' \
  "$PLUGIN_ROOT/skills/rnd-reality-auditing/SKILL.md" \
  "$CANONICAL_MANIFEST"

assert_file_contains_text \
  'cleanup skill reads the canonical manifest filename' \
  "$PLUGIN_ROOT/skills/rnd-cleanup/SKILL.md" \
  "$CANONICAL_MANIFEST"

assert_file_contains_text \
  'builder agent uses the canonical manifest filename' \
  "$PLUGIN_ROOT/agents/rnd-builder.md" \
  "$CANONICAL_MANIFEST"

assert_file_not_contains_text \
  'builder agent no longer uses the legacy manifest filename as primary guidance' \
  "$PLUGIN_ROOT/agents/rnd-builder.md" \
  '$RND_DIR/builds/T<id>-manifest.md'

assert_file_contains_text \
  'integrator agent uses the canonical manifest filename' \
  "$PLUGIN_ROOT/agents/rnd-integrator.md" \
  "$CANONICAL_MANIFEST"

assert_file_not_contains_text \
  'integrator agent no longer uses the legacy manifest filename as primary guidance' \
  "$PLUGIN_ROOT/agents/rnd-integrator.md" \
  '$RND_DIR/builds/T<id>-manifest.md'

assert_file_contains_text \
  'polisher agent uses the canonical manifest filename' \
  "$PLUGIN_ROOT/agents/rnd-polisher.md" \
  "$CANONICAL_MANIFEST"

assert_file_not_contains_text \
  'polisher agent no longer uses the legacy manifest filename as primary guidance' \
  "$PLUGIN_ROOT/agents/rnd-polisher.md" \
  '$RND_DIR/builds/T<id>-manifest.md'

assert_file_contains_text \
  'reality-auditor agent uses the canonical manifest filename' \
  "$PLUGIN_ROOT/agents/rnd-reality-auditor.md" \
  "$CANONICAL_MANIFEST"

assert_file_not_contains_text \
  'reality-auditor agent no longer uses the legacy manifest filename as primary guidance' \
  "$PLUGIN_ROOT/agents/rnd-reality-auditor.md" \
  '$RND_DIR/builds/T<id>-manifest.md'

assert_file_contains_text \
  'build skill uses the canonical manifest filename' \
  "$PLUGIN_ROOT/skills/rnd-build/SKILL.md" \
  "$CANONICAL_MANIFEST"

assert_file_not_contains_text \
  'build skill no longer uses the legacy manifest filename as primary guidance' \
  "$PLUGIN_ROOT/skills/rnd-build/SKILL.md" \
  '$RND_DIR/builds/T<id>-manifest.md'

assert_file_contains_text \
  'narrative skill uses the canonical manifest filename or canonical glob' \
  "$PLUGIN_ROOT/skills/rnd-narrative/SKILL.md" \
  'M<NN>-T<NN>-<uuid>-manifest.md'

assert_file_not_contains_text \
  'narrative skill no longer uses the legacy manifest glob as the primary guidance' \
  "$PLUGIN_ROOT/skills/rnd-narrative/SKILL.md" \
  '$RND_DIR/builds/T*-manifest.md'

assert_file_contains_text \
  'history command explains the branch-partitioned session base' \
  "$PLUGIN_ROOT/commands/rnd-history.md" \
  'branch-scoped base directory'

assert_file_contains_text \
  'calibrate skill explains the branch-scoped base partition' \
  "$PLUGIN_ROOT/skills/rnd-calibrate/SKILL.md" \
  'branch-scoped base dir under `.../branches/<branch>/`'

assert_file_contains_text \
  'calibrate skill shows the branch-partitioned session path' \
  "$PLUGIN_ROOT/skills/rnd-calibrate/SKILL.md" \
  'branches/<branch>/sessions/<session-id>/verifications/<task-id>-verification.md'

assert_file_contains_text \
  'orchestration skill shows the branch-partitioned session path' \
  "$PLUGIN_ROOT/skills/rnd-orchestration/SKILL.md" \
  'branches/<branch>/sessions/<YYYYMMDD-HHMMSS-XXXX>/'

printf '\n--- command-doc-and-prose-consistency ---\n'

assert_file_contains_text \
  'rnd-audit uses the canonical audit report path' \
  "$AUDIT_COMMAND" \
  '$RND_DIR/audit-report.md'

assert_file_not_contains_text \
  'rnd-audit no longer references the legacy audit report directory path' \
  "$AUDIT_COMMAND" \
  '$RND_DIR/audit/'

assert_file_contains_text \
  'rnd-review uses the canonical review report path' \
  "$REVIEW_COMMAND" \
  '$RND_DIR/review-report.md'

assert_file_not_contains_text \
  'rnd-review no longer references the legacy review report directory path' \
  "$REVIEW_COMMAND" \
  '$RND_DIR/review/'

assert_file_contains_text \
  'rnd-review describes seven review categories' \
  "$REVIEW_COMMAND" \
  'seven review categories'

assert_file_not_contains_text \
  'rnd-review no longer describes six review categories' \
  "$REVIEW_COMMAND" \
  'six review categories'

assert_file_contains_text \
  'site intro install fence is language-tagged' \
  "$SITE_INTRO" \
  '```bash'

assert_file_not_contains_text \
  'hooks lib no longer uses the audited FM1 label' \
  "$HOOK_LIB" \
  'FM1'

assert_file_not_contains_text \
  'post-review writer no longer uses milestone-specific example labels' \
  "$POST_REVIEW_WRITER" \
  'M1.T01 and M2.T01'

assert_file_not_contains_text \
  'post-review writer no longer uses the audited FM4 label' \
  "$POST_REVIEW_WRITER" \
  'FM4'

assert_file_not_contains_text \
  'rnd-stats no longer uses the audited M3 label' \
  "$STATS_COMMAND" \
  'M3'

assert_file_not_contains_text \
  'rnd-stats no longer uses the audited M12 label' \
  "$STATS_COMMAND" \
  'M12'

report
