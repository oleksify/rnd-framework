#!/usr/bin/env bash
# tests/hermeticity.test.sh — Standing regression guard for test-suite hermeticity.
# Proves the isolation layers are load-bearing (not vacuously passing) and that
# no future test can silently reintroduce ambient-env leakage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"

DIRTY_CONFIG="$(mktemp -d)"
DIRTY_HOME="$(mktemp -d)"
trap 'rm -rf "$DIRTY_CONFIG" "$DIRTY_HOME"' EXIT

# --- 1. The preamble is load-bearing (control vs treatment) ---
# Control: an un-isolated subshell inherits the dirty CLAUDE_CONFIG_DIR verbatim.
# This proves the dirty fixture is real, so the treatment below is meaningful.
control_cfg="$(env CLAUDE_CONFIG_DIR="$DIRTY_CONFIG" bash -c 'printf "%s" "${CLAUDE_CONFIG_DIR:-}"')"
assert_eq "control: an un-isolated subshell sees the dirty CLAUDE_CONFIG_DIR" "$DIRTY_CONFIG" "$control_cfg"

# Treatment: sourcing test-helpers.sh re-points CLAUDE_CONFIG_DIR away from the dirty value.
treated_cfg="$(env CLAUDE_CONFIG_DIR="$DIRTY_CONFIG" HOME="$DIRTY_HOME" RND_DIR="/nonexistent/leak" \
  bash -c "source '${SCRIPT_DIR}/test-helpers.sh'; printf '%s' \"\${CLAUDE_CONFIG_DIR:-}\"")"
cfg_scrubbed=$([[ -n "$treated_cfg" && "$treated_cfg" != "$DIRTY_CONFIG" ]] && echo scrubbed || echo leaked)
assert_eq "preamble re-points CLAUDE_CONFIG_DIR off the dirty value" "scrubbed" "$cfg_scrubbed"

# Treatment: the preamble unsets a stale RND_DIR rather than inheriting it.
treated_rnd="$(env RND_DIR="/nonexistent/leak" \
  bash -c "source '${SCRIPT_DIR}/test-helpers.sh'; printf '%s' \"\${RND_DIR:-UNSET}\"")"
assert_eq "preamble unsets a stale RND_DIR" "UNSET" "$treated_rnd"

# --- 2. The harness scrubs each test file at the chokepoint ---
assert_contains "run-tests.sh runs each test under env -i" "env -i" "$(cat "${SCRIPT_DIR}/run-tests.sh")"

# --- 3. No isolation guard uses the := no-op form (it is a no-op when the var is already set) ---
noop_guards="$(grep -rnE ':[[:space:]]*"\$\{(CLAUDE_CONFIG_DIR|HOME|RND_DIR):=' "$SCRIPT_DIR" || true)"
assert_eq "no := no-op isolation guards anywhere in tests/" "" "$noop_guards"

# --- 4. Every non-sourcing test carries an explicit unconditional guard ---
# This is the real future regression: a new test that neither sources test-helpers.sh
# nor guards itself would silently reintroduce ambient leakage.
unguarded=""
while IFS= read -r test_file; do
  grep -q 'test-helpers.sh' "$test_file" && continue
  grep -qE '^export CLAUDE_CONFIG_DIR="\$\(mktemp -d\)"' "$test_file" || unguarded+=" $(basename "$test_file")"
done < <(ls "${SCRIPT_DIR}"/*.test.sh)
assert_eq "every non-sourcing test carries an unconditional CLAUDE_CONFIG_DIR guard" "" "$unguarded"

# --- 5. Behavioural: a per-file-guarded non-sourcing test passes under a dirty env ---
task_exit=0
env CLAUDE_CONFIG_DIR="$DIRTY_CONFIG" HOME="$DIRTY_HOME" RND_DIR="/nonexistent/leak" \
  bash "${SCRIPT_DIR}/task-created.test.sh" >/dev/null 2>&1 || task_exit=$?
assert_eq "a guarded non-sourcing test (task-created) passes under a dirty ambient env" "0" "$task_exit"

report
