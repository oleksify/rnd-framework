#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PLUGIN_ROOT}/../.." && pwd)"

failures=0

require_text() {
  local file="$1"
  local text="$2"

  if grep -Fq "$text" "$file"; then
    return 0
  fi

  printf 'FAIL|missing-text|%s|%s\n' "${file#$REPO_ROOT/}" "$text"
  failures=$((failures + 1))

  return 1
}

emit_ok() {
  local finding_class="$1"
  shift

  printf 'OK|%s' "$finding_class"

  while [[ $# -gt 0 ]]; do
    printf '|%s' "$1"
    shift
  done

  printf '\n'
}

check_hook_path_overmatch() {
  local lib_file="$PLUGIN_ROOT/hooks/lib.sh"
  local read_test="$PLUGIN_ROOT/tests/read-gate.test.sh"
  local write_test="$PLUGIN_ROOT/tests/write-gate.test.sh"

  require_text "$lib_file" '/tmp/project/.claude-evil/x/.rnd/'
  require_text "$read_test" 'fake artifact-root bypass path → empty stdout (no auto-allow)'
  require_text "$write_test" 'Write fake artifact-root bypass path → empty stdout (no auto-allow)'

  emit_ok \
    'hook-path-overmatch' \
    'plugins/rnd-framework/hooks/lib.sh' \
    'plugins/rnd-framework/tests/read-gate.test.sh' \
    'plugins/rnd-framework/tests/write-gate.test.sh'
}

check_destructive_git_bypass() {
  local gate_test="$PLUGIN_ROOT/tests/bash-gate-destructive-git.test.sh"

  require_text "$gate_test" 'FOO="a b" git reset --hard HEAD'
  require_text "$gate_test" 'git --work-tree /repo checkout .'

  emit_ok \
    'destructive-git-bypass' \
    'plugins/rnd-framework/hooks/bash-gate.sh' \
    'plugins/rnd-framework/tests/bash-gate-destructive-git.test.sh'
}

check_post_review_quality_debt() {
  local writer="$PLUGIN_ROOT/lib/post-review-writer.sh"
  local test_file="$PLUGIN_ROOT/tests/post-review-writer.test.sh"

  require_text "$writer" 'PASS_QUALITY_NEEDS_ITERATION is still open quality debt'
  require_text "$test_file" 'F3: PASS_QUALITY_NEEDS_ITERATION owning task → false'

  emit_ok \
    'post-review-quality-debt' \
    'plugins/rnd-framework/lib/post-review-writer.sh' \
    'plugins/rnd-framework/tests/post-review-writer.test.sh'
}

check_per_shape_session_join() {
  local sql_file="$PLUGIN_ROOT/lib/stats/per_shape_fail_rate.sql"
  local test_file="$PLUGIN_ROOT/tests/outside-view-query.test.sh"

  require_text "$sql_file" 'repeated task ids across sessions cannot cross-count shapes.'
  require_text "$sql_file" 'ON v.session_id = t.session_id'
  require_text "$test_file" 'per_shape_fail_rate joins on session_id + task_id'

  emit_ok \
    'per-shape-session-join' \
    'plugins/rnd-framework/lib/stats/per_shape_fail_rate.sql' \
    'plugins/rnd-framework/tests/outside-view-query.test.sh'
}

check_backfill_session_id_fallback() {
  local sql_file="$PLUGIN_ROOT/lib/stats/backfill.sql"
  local test_file="$PLUGIN_ROOT/tests/outside-view-query.test.sh"

  require_text "$sql_file" "COALESCE(TRY(json_extract_string(j, '$.session_id')), TRY(json_extract_string(j, '$.sessionId'))) AS session_id"
  require_text "$test_file" 'backfill: snake_case session_id preserved'
  require_text "$test_file" 'backfill: camelCase sessionId still supported'

  emit_ok \
    'backfill-session-id-fallback' \
    'plugins/rnd-framework/lib/stats/backfill.sql' \
    'plugins/rnd-framework/tests/outside-view-query.test.sh'
}

check_sycophancy_head_fallback() {
  local script_file="$PLUGIN_ROOT/lib/sycophancy-probe.sh"
  local test_file="$PLUGIN_ROOT/tests/sycophancy-probe.test.sh"

  require_text "$script_file" 'head_fallback'
  require_text "$test_file" 'prepare: HEAD fallback artifact keeps head_fallback basis'

  emit_ok \
    'sycophancy-head-fallback' \
    'plugins/rnd-framework/lib/sycophancy-probe.sh' \
    'plugins/rnd-framework/tests/sycophancy-probe.test.sh'
}

check_verifier_prose_report_contract() {
  local skill_file="$PLUGIN_ROOT/skills/rnd-verify/SKILL.md"
  local test_file="$PLUGIN_ROOT/tests/verifier-artifact-contract.test.sh"

  require_text "$skill_file" 'For every verdict class (PASS, PASS_QUALITY_NEEDS_ITERATION, NEEDS_ITERATION, and FAIL), the Verifier writes `T<id>-verification.md`'
  require_text "$skill_file" 'does not replace `T<id>-verification.md`'
  require_text "$test_file" 'verify skill no longer says PASS skips the prose report'

  emit_ok \
    'verifier-prose-report-contract' \
    'plugins/rnd-framework/skills/rnd-verify/SKILL.md' \
    'plugins/rnd-framework/tests/verifier-artifact-contract.test.sh'
}

check_validate_xrefs_negative_coverage() {
  local test_file="$PLUGIN_ROOT/tests/validator-regressions.test.sh"

  require_text "$test_file" 'validate_cross_refs'
  require_text "$test_file" 'sourced xrefs records the broken reference through record_fail'

  emit_ok \
    'validate-xrefs-negative-coverage' \
    'plugins/rnd-framework/tests/validator-regressions.test.sh'
}

check_validate_sh_negative_coverage() {
  local test_file="$PLUGIN_ROOT/tests/validator-regressions.test.sh"

  require_text "$test_file" 'plugin.json not found'
  require_text "$test_file" "plugin.json missing 'version'"
  require_text "$test_file" 'healthy plugin exits 0'

  emit_ok \
    'validate-sh-negative-coverage' \
    'plugins/rnd-framework/tests/validator-regressions.test.sh'
}

check_command_and_docs_drift() {
  local plugin_readme="$PLUGIN_ROOT/README.md"
  local root_claude="$REPO_ROOT/CLAUDE.md"
  local test_file="$PLUGIN_ROOT/tests/docs-contract.test.sh"

  require_text "$plugin_readme" 'tracked in `plugins/rnd-framework/commands/*.md`'
  require_text "$root_claude" '/rnd-framework:rnd-start'
  require_text "$test_file" 'plugin README command inventory matches tracked command files'
  require_text "$test_file" 'root CLAUDE command inventory matches tracked command files'

  emit_ok \
    'command-and-docs-drift' \
    'plugins/rnd-framework/README.md' \
    'CLAUDE.md' \
    'plugins/rnd-framework/tests/docs-contract.test.sh'
}

check_pipeline_artifact_session_docs() {
  local root_readme="$REPO_ROOT/README.md"
  local status_command="$PLUGIN_ROOT/commands/rnd-status.md"
  local orchestration_skill="$PLUGIN_ROOT/skills/rnd-orchestration/SKILL.md"
  local test_file="$PLUGIN_ROOT/tests/docs-contract.test.sh"

  require_text "$root_readme" 'Scope → Plan → Schedule → Build → [Reality Audit] → Verify → [Iterate] → Cleanup → Polish → Integrate → [Post-Review]'
  require_text "$status_command" 'M<NN>-T<NN>-<uuid>-manifest.md'
  require_text "$orchestration_skill" 'branches/<branch>/sessions/<YYYYMMDD-HHMMSS-XXXX>/'
  require_text "$test_file" 'orchestration skill shows the branch-partitioned session path'

  emit_ok \
    'pipeline-artifact-session-docs' \
    'README.md' \
    'plugins/rnd-framework/commands/rnd-status.md' \
    'plugins/rnd-framework/skills/rnd-orchestration/SKILL.md' \
    'plugins/rnd-framework/tests/docs-contract.test.sh'
}

check_hook_path_overmatch
check_destructive_git_bypass
check_post_review_quality_debt
check_per_shape_session_join
check_backfill_session_id_fallback
check_sycophancy_head_fallback
check_verifier_prose_report_contract
check_validate_xrefs_negative_coverage
check_validate_sh_negative_coverage
check_command_and_docs_drift
check_pipeline_artifact_session_docs

if [[ $failures -ne 0 ]]; then
  exit 1
fi
