#!/usr/bin/env bash
# tests/bash-gate-rnd-dir-boundary.test.sh — Tests for rnd-dir.sh auto-allow boundary regex
# and protected-branch push advisories for branch, HEAD:<branch>, and refs/heads/<branch> targets.
# Usage: bash tests/bash-gate-rnd-dir-boundary.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

BASH_GATE="${SCRIPT_DIR}/../hooks/bash-gate.sh"

_make_json() {
  local cmd="$1"
  local agent="${2:-rnd-builder}"

  jq -nc --arg command "$cmd" --arg agent "$agent" '{tool_name:"Bash", tool_input:{command:$command}, agent_type:$agent}'
}

printf '\n--- bash-gate: rnd-dir.sh boundary regex ---\n'

# Case 1: rnd-dir.sh as a path token — must be auto-allowed.
run_hook "$BASH_GATE" \
  "$(_make_json 'bash /some/path/rnd-dir.sh')"
assert_exit_code "Case 1: rnd-dir.sh as path token is auto-allowed" 0

# Case 3: rnd-dir.sh in middle of arg list is NOT auto-allowed via the rnd-dir.sh substring path.
# The boundary regex requires `^|/` as leading boundary — a leading SPACE does not count.
# Without this strictness, `cat rnd-dir.sh some-other-file.txt` would auto-allow because
# "rnd-dir.sh" appears with space boundaries — a false positive flagged in the audit.
# The Read tool is not blocked by tool discipline and not auto-allowed by the .claude*/.rnd/ branch,
# so the only path to auto-allow for this command is the rnd-dir.sh boundary regex itself.
run_hook "$BASH_GATE" \
  "$(_make_json 'cat rnd-dir.sh some-other-file.txt')"
assert_exit_code "Case 3: cat rnd-dir.sh ... exits 0 (no opinion, not auto-allowed via substring)" 0
_case3_has_allow="0"
[[ "$HOOK_STDOUT" == *'"permissionDecision":"allow"'* ]] && _case3_has_allow="1"
assert_eq "Case 3: cat rnd-dir.sh ... is NOT auto-allowed (stdout has no allow JSON)" "0" "$_case3_has_allow"

# Case 3b: rnd-dir.sh as a path token (preceded by /) IS auto-allowed — true positive preserved.
run_hook "$BASH_GATE" \
  "$(_make_json 'bash /path/rnd-dir.sh')"
assert_exit_code "Case 3b: bash /path/rnd-dir.sh exits 0" 0
_case3b_has_allow="0"
[[ "$HOOK_STDOUT" == *'"permissionDecision":"allow"'* ]] && _case3b_has_allow="1"
assert_eq "Case 3b: bash /path/rnd-dir.sh IS auto-allowed (stdout contains allow JSON)" "1" "$_case3b_has_allow"

printf '\n--- bash-gate: push protected-target advisories ---\n'

# Case 4: git push origin main, existing branch-name target stays covered.
run_hook "$BASH_GATE" \
  "$(_make_json 'git push origin main')"
assert_exit_code "Case 4: git push main exits 0 (advisory not block)" 0
assert_contains "Case 4: stdout contains WARNING for main push" "WARNING" "$HOOK_STDOUT"

# Case 5: git push origin HEAD:main — must trigger protected-branch advisory (exit 0, WARNING).
run_hook "$BASH_GATE" \
  "$(_make_json 'git push origin HEAD:main')"
assert_exit_code "Case 5: git push HEAD:main exits 0 (advisory not block)" 0
assert_contains "Case 5: stdout contains WARNING for HEAD:main push" "WARNING" "$HOOK_STDOUT"

# Case 6: git push origin HEAD:master — must also trigger advisory.
run_hook "$BASH_GATE" \
  "$(_make_json 'git push origin HEAD:master')"
assert_exit_code "Case 6: git push HEAD:master exits 0 (advisory)" 0
assert_contains "Case 6: stdout contains WARNING for HEAD:master push" "WARNING" "$HOOK_STDOUT"

# Case 7: git push origin refs/heads/main — full ref target must trigger advisory.
run_hook "$BASH_GATE" \
  "$(_make_json 'git push origin refs/heads/main')"
assert_exit_code "Case 7: git push refs/heads/main exits 0 (advisory)" 0
assert_contains "Case 7: stdout contains WARNING for refs/heads/main push" "WARNING" "$HOOK_STDOUT"

# Case 8: git push origin refs/heads/master — full ref target must trigger advisory.
run_hook "$BASH_GATE" \
  "$(_make_json 'git push origin refs/heads/master')"
assert_exit_code "Case 8: git push refs/heads/master exits 0 (advisory)" 0
assert_contains "Case 8: stdout contains WARNING for refs/heads/master push" "WARNING" "$HOOK_STDOUT"

# Case 9: git push origin refs/heads/production — full ref target must trigger advisory.
run_hook "$BASH_GATE" \
  "$(_make_json 'git push origin refs/heads/production')"
assert_exit_code "Case 9: git push refs/heads/production exits 0 (advisory)" 0
assert_contains "Case 9: stdout contains WARNING for refs/heads/production push" "WARNING" "$HOOK_STDOUT"

# Case 10: git push origin HEAD:feature-branch — must NOT trigger advisory.
run_hook "$BASH_GATE" \
  "$(_make_json 'git push origin HEAD:feature-branch')"
assert_exit_code "Case 10: git push HEAD:feature-branch exits 0 (no advisory)" 0
_case10_has_warning="0"
[[ "$HOOK_STDOUT" == *"WARNING"* ]] && _case10_has_warning="1"
assert_eq "Case 10: stdout must NOT contain WARNING for non-protected branch" "0" "$_case10_has_warning"

report
