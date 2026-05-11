#!/usr/bin/env bash
# tests/branch-keying.test.sh — Targeted tests for branch-keying behavior.
# Covers VAL-BSCOPE-001,002,003,004,005,006, VAL-CALIB-001, VAL-INHERIT-001,002,003, VAL-PDBID-001.
# Usage: bash tests/branch-keying.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RND_DIR_SCRIPT="${REPO_ROOT}/lib/rnd-dir.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMPBASE="$(mktemp -d)"
trap 'rm -rf "$TMPBASE"' EXIT

# ---------------------------------------------------------------------------
# Helper: create a scratch git repo with a named branch checked out.
# ---------------------------------------------------------------------------
make_git_repo() {
  local dir="$1" branch="${2:-main}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" checkout -q -b "$branch" 2>/dev/null || git -C "$dir" checkout -q "$branch"
  git -C "$dir" commit -q --allow-empty -m "init"
}

# ---------------------------------------------------------------------------
# VAL-BSCOPE-001: --base returns path containing /branches/<branch>/
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-BSCOPE-001: --base includes /branches/<branch>/ ---'

REPO1="${TMPBASE}/repo1"
CFG1="${TMPBASE}/cfg1"
make_git_repo "$REPO1" "main"

BASE_OUT="$(CLAUDE_CONFIG_DIR="$CFG1" bash "$RND_DIR_SCRIPT" --base 2>/dev/null)" || true

if [[ "$BASE_OUT" == */branches/main/* || "$BASE_OUT" == */branches/main ]]; then
  assert_eq "VAL-BSCOPE-001: --base contains /branches/main/" "yes" "yes"
else
  assert_eq "VAL-BSCOPE-001: --base contains /branches/main/" "yes" "no: '$BASE_OUT'"
fi

# ---------------------------------------------------------------------------
# VAL-BSCOPE-002: -c places session under branches/<branch>/sessions/
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-BSCOPE-002: -c places session under branches/<branch>/sessions/ ---'

REPO2="${TMPBASE}/repo2"
CFG2="${TMPBASE}/cfg2"
make_git_repo "$REPO2" "feature-x"

SESSION_OUT="$(cd "$REPO2" && CLAUDE_CONFIG_DIR="$CFG2" bash "$RND_DIR_SCRIPT" -c 2>/dev/null)"

if [[ "$SESSION_OUT" == */branches/feature-x/sessions/* ]]; then
  assert_eq "VAL-BSCOPE-002: session path contains /branches/feature-x/sessions/" "yes" "yes"
else
  assert_eq "VAL-BSCOPE-002: session path contains /branches/feature-x/sessions/" "yes" "no: '$SESSION_OUT'"
fi

if [[ -d "$SESSION_OUT" ]]; then
  assert_eq "VAL-BSCOPE-002: session directory exists" "yes" "yes"
else
  assert_eq "VAL-BSCOPE-002: session directory exists" "yes" "no: '$SESSION_OUT'"
fi

# ---------------------------------------------------------------------------
# VAL-BSCOPE-003: Two branches produce non-overlapping paths
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-BSCOPE-003: two branches produce non-overlapping paths ---'

REPO_A="${TMPBASE}/repo_a"
REPO_B="${TMPBASE}/repo_b"
CFG_A="${TMPBASE}/cfg_a"

make_git_repo "$REPO_A" "main"
cp -r "${REPO_A}/.git" "${REPO_B}/"
mkdir -p "$REPO_B"
git -C "$REPO_B" checkout -q -b "develop" 2>/dev/null || true

BASE_A="$(cd "$REPO_A" && CLAUDE_CONFIG_DIR="$CFG_A" bash "$RND_DIR_SCRIPT" --base 2>/dev/null)"
BASE_B="$(cd "$REPO_B" && CLAUDE_CONFIG_DIR="$CFG_A" bash "$RND_DIR_SCRIPT" --base 2>/dev/null)"

if [[ "$BASE_A" != "$BASE_B" ]]; then
  assert_eq "VAL-BSCOPE-003: two branches have distinct --base paths" "distinct" "distinct"
else
  assert_eq "VAL-BSCOPE-003: two branches have distinct --base paths" "distinct" "same: '$BASE_A'"
fi

BASE_A_NORM="${BASE_A%/}"
BASE_B_NORM="${BASE_B%/}"

if [[ "$BASE_A_NORM" != "${BASE_B_NORM}"* && "$BASE_B_NORM" != "${BASE_A_NORM}"* ]]; then
  assert_eq "VAL-BSCOPE-003: paths do not nest (no common mutable parent)" "non-nested" "non-nested"
else
  assert_eq "VAL-BSCOPE-003: paths do not nest (no common mutable parent)" "non-nested" "nested: '$BASE_A_NORM' vs '$BASE_B_NORM'"
fi

if [[ "$BASE_A" == */branches/* && "$BASE_B" == */branches/* ]]; then
  assert_eq "VAL-BSCOPE-003: both paths are branch-scoped (contain /branches/)" "yes" "yes"
else
  assert_eq "VAL-BSCOPE-003: both paths are branch-scoped (contain /branches/)" "yes" "no: '$BASE_A' / '$BASE_B'"
fi

# ---------------------------------------------------------------------------
# VAL-CALIB-001: --calibration returns <slug>/calibration.jsonl (no /branches/)
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-CALIB-001: --calibration returns slug-root path ---'

REPO3="${TMPBASE}/repo3"
CFG3="${TMPBASE}/cfg3"
make_git_repo "$REPO3" "my-branch"

CALIB_OUT="$(cd "$REPO3" && CLAUDE_CONFIG_DIR="$CFG3" bash "$RND_DIR_SCRIPT" --calibration 2>/dev/null)"

if [[ "$CALIB_OUT" == */calibration.jsonl && "$CALIB_OUT" != */branches/* ]]; then
  assert_eq "VAL-CALIB-001: --calibration has no /branches/ component" "yes" "yes"
else
  assert_eq "VAL-CALIB-001: --calibration has no /branches/ component" "yes" "no: '$CALIB_OUT'"
fi

# ---------------------------------------------------------------------------
# VAL-BSCOPE-004: Detached HEAD → branches/detached-<sha7>/
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-BSCOPE-004: Detached HEAD produces detached-<sha> bucket ---'

REPO4="${TMPBASE}/repo4"
CFG4="${TMPBASE}/cfg4"
make_git_repo "$REPO4" "main"

COMMIT_SHA="$(git -C "$REPO4" rev-parse --short HEAD)"
git -C "$REPO4" checkout -q --detach "$COMMIT_SHA" 2>/dev/null

DETACHED_OUT="$(cd "$REPO4" && CLAUDE_CONFIG_DIR="$CFG4" bash "$RND_DIR_SCRIPT" --base 2>/dev/null)"

if [[ "$DETACHED_OUT" == */branches/detached-* ]]; then
  assert_eq "VAL-BSCOPE-004: detached HEAD path contains /branches/detached-" "yes" "yes"
else
  assert_eq "VAL-BSCOPE-004: detached HEAD path contains /branches/detached-" "yes" "no: '$DETACHED_OUT'"
fi

# ---------------------------------------------------------------------------
# VAL-BSCOPE-005: Non-git directory → branches/no-git/
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-BSCOPE-005: Non-git dir produces branches/no-git/ bucket ---'

NONGIT="${TMPBASE}/nongit"
CFG5="${TMPBASE}/cfg5"
mkdir -p "$NONGIT"

NOGIT_OUT="$(cd "$NONGIT" && CLAUDE_CONFIG_DIR="$CFG5" bash "$RND_DIR_SCRIPT" --base 2>/dev/null)"

if [[ "$NOGIT_OUT" == */branches/no-git || "$NOGIT_OUT" == */branches/no-git/* ]]; then
  assert_eq "VAL-BSCOPE-005: non-git path contains /branches/no-git" "yes" "yes"
else
  assert_eq "VAL-BSCOPE-005: non-git path contains /branches/no-git" "yes" "no: '$NOGIT_OUT'"
fi

# ---------------------------------------------------------------------------
# VAL-BSCOPE-006: Branch name containing ".." causes exit non-zero
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-BSCOPE-006: Branch name with ".." causes exit non-zero ---'

REPO6="${TMPBASE}/repo6"
CFG6="${TMPBASE}/cfg6"
make_git_repo "$REPO6" "main"

FAKEGIT="${TMPBASE}/fake-git6"
mkdir -p "$FAKEGIT"
printf '%s\n' '#!/usr/bin/env bash
if [[ "$1" = "symbolic-ref" ]]; then
  printf '"'"'feat/../../evil'"'"'
  exit 0
fi
exec /usr/bin/git "$@"' > "${FAKEGIT}/git"
chmod +x "${FAKEGIT}/git"

DOTDOT_EXIT=0
PATH="${FAKEGIT}:$PATH" CLAUDE_CONFIG_DIR="$CFG6" bash "$RND_DIR_SCRIPT" --base >/dev/null 2>&1 || DOTDOT_EXIT=$?

if [[ "$DOTDOT_EXIT" -ne 0 ]]; then
  assert_eq "VAL-BSCOPE-006: '..' in branch name causes non-zero exit" "non-zero" "non-zero"
else
  assert_eq "VAL-BSCOPE-006: '..' in branch name causes non-zero exit" "non-zero" "zero"
fi

# ---------------------------------------------------------------------------
# VAL-INHERIT-001: --facts copies from default branch when branch-scoped file absent
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-INHERIT-001: --facts copies from default branch when missing ---'

REPO7="${TMPBASE}/repo7"
CFG7="${TMPBASE}/cfg7"
make_git_repo "$REPO7" "main"

SLUG7="$(cd "$REPO7" && CLAUDE_CONFIG_DIR="$CFG7" bash "$RND_DIR_SCRIPT" --base 2>/dev/null)"
SLUG7_ROOT="${SLUG7%/branches/*}"
MAIN_FACTS="${SLUG7_ROOT}/branches/main/project-facts.md"
mkdir -p "$(dirname "$MAIN_FACTS")"
printf 'facts content\n' > "$MAIN_FACTS"

git -C "$REPO7" checkout -q -b "feature-y" 2>/dev/null
FEATURE_BASE="${SLUG7_ROOT}/branches/feature-y"

FACTS_OUT="$(cd "$REPO7" && CLAUDE_CONFIG_DIR="$CFG7" bash "$RND_DIR_SCRIPT" --facts 2>/dev/null)"
INHERITED_FILE="${FEATURE_BASE}/project-facts.md"

if [[ -f "$INHERITED_FILE" ]]; then
  assert_eq "VAL-INHERIT-001: project-facts.md copied to feature branch dir" "yes" "yes"
else
  assert_eq "VAL-INHERIT-001: project-facts.md copied to feature branch dir" "yes" "no: '$FACTS_OUT'"
fi

INHERITED_CONTENT="$(cat "$INHERITED_FILE" 2>/dev/null || echo '')"
assert_eq "VAL-INHERIT-001: inherited file has correct content" "facts content" "$INHERITED_CONTENT"

# ---------------------------------------------------------------------------
# VAL-INHERIT-002: --facts skips self-copy when on default branch
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-INHERIT-002: --facts skips self-copy on default branch ---'

REPO8="${TMPBASE}/repo8"
CFG8="${TMPBASE}/cfg8"
make_git_repo "$REPO8" "main"

FACTS_OUT8=""
FACTS_EXIT8=0
FACTS_OUT8="$(cd "$REPO8" && CLAUDE_CONFIG_DIR="$CFG8" bash "$RND_DIR_SCRIPT" --facts 2>/dev/null)" || FACTS_EXIT8=$?

assert_eq "VAL-INHERIT-002: --facts exits 0 on default branch" "0" "$FACTS_EXIT8"
assert_eq "VAL-INHERIT-002: --facts returns path ending in project-facts.md" "yes" \
  "$(if [[ "$FACTS_OUT8" == */project-facts.md ]]; then echo yes; else echo "no: $FACTS_OUT8"; fi)"

# ---------------------------------------------------------------------------
# VAL-INHERIT-003: --facts exits 0 with no file created when neither branch has artifact
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-INHERIT-003: --facts exits 0 when no branch has artifact ---'

REPO9="${TMPBASE}/repo9"
CFG9="${TMPBASE}/cfg9"
make_git_repo "$REPO9" "main"
git -C "$REPO9" checkout -q -b "feature-z" 2>/dev/null

FACTS_OUT9=""
FACTS_EXIT9=0
FACTS_OUT9="$(cd "$REPO9" && CLAUDE_CONFIG_DIR="$CFG9" bash "$RND_DIR_SCRIPT" --facts 2>/dev/null)" || FACTS_EXIT9=$?

assert_eq "VAL-INHERIT-003: --facts exits 0 when no artifact exists anywhere" "0" "$FACTS_EXIT9"

BASE9="$(cd "$REPO9" && CLAUDE_CONFIG_DIR="$CFG9" bash "$RND_DIR_SCRIPT" --base 2>/dev/null)"
if [[ ! -f "${BASE9}/project-facts.md" ]]; then
  assert_eq "VAL-INHERIT-003: no project-facts.md created when neither branch has it" "yes" "yes"
else
  assert_eq "VAL-INHERIT-003: no project-facts.md created when neither branch has it" "yes" "no: file exists"
fi

# ---------------------------------------------------------------------------
# VAL-PDBID-001: Both copies of plugin-dir-base.sh are byte-identical
# ---------------------------------------------------------------------------
printf '%s\n' '--- VAL-PDBID-001: both plugin-dir-base.sh copies are byte-identical ---'

CANONICAL="${REPO_ROOT}/../../lib/plugin-dir-base.sh"
RND_COPY="${REPO_ROOT}/lib/plugin-dir-base.sh"

if diff -q "$CANONICAL" "$RND_COPY" >/dev/null 2>&1; then
  assert_eq "VAL-PDBID-001: lib/plugin-dir-base.sh identical to plugins/rnd-framework/lib/plugin-dir-base.sh" "identical" "identical"
else
  assert_eq "VAL-PDBID-001: lib/plugin-dir-base.sh identical to plugins/rnd-framework/lib/plugin-dir-base.sh" "identical" "differs"
fi

report
