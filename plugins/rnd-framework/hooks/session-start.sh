#!/usr/bin/env bash
# hooks/session-start.sh — SessionStart hook for rnd-framework plugin.
# Injects the using-rnd-framework skill content into session context and checks
# for a version mismatch between the cached plugin and the source in the git root.
#
# Always exits 0. Outputs SessionStart JSON with hookSpecificOutput.additionalContext.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

readonly SKILL_PATH="${PLUGIN_ROOT}/skills/using-rnd-framework/SKILL.md"
readonly CACHED_PLUGIN="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

# Headers at which to trim the skill for token efficiency (first match wins)
readonly TRIM_HEADERS="^## Data Science Tasks$|^## Pipeline Scaling$|^## Skill Priority$|^## Skill Types$|^## Red Flags$"

# ---------------------------------------------------------------------------
# Read and process SKILL.md
# ---------------------------------------------------------------------------

skill_content=""

if [[ -f "$SKILL_PATH" ]]; then
  # Strip YAML frontmatter using lib.sh strip_frontmatter
  raw_content="$(strip_frontmatter < "$SKILL_PATH" 2>/dev/null || true)"

  # Trim at first verbose section header to limit token usage
  trim_line="$(printf '%s\n' "$raw_content" | grep -n -m1 -E "$TRIM_HEADERS" \
    2>/dev/null | cut -d: -f1 | head -1 || true)"

  if [[ -n "$trim_line" && "$trim_line" -gt 0 ]]; then
    skill_content="$(printf '%s\n' "$raw_content" | awk -v n="$((trim_line - 1))" 'NR<=n')"
  else
    skill_content="$raw_content"
  fi

  # Trim leading/trailing blank lines (preserve internal indentation)
  skill_content="$(printf '%s' "$skill_content" | \
    awk 'NF{found=1} found{print}' | \
    awk '{lines[NR]=$0} NF{last=NR} END{for(i=1;i<=last;i++) print lines[i]}')"
else
  skill_content="Error reading using-rnd-framework skill"
fi

# ---------------------------------------------------------------------------
# Get RND_DIR and record git root for cross-repo detection (cwd-changed.sh)
# ---------------------------------------------------------------------------

rnd_dir="$(resolve_rnd_dir -c 2>/dev/null || true)"
rnd_line=""
if [[ -n "$rnd_dir" ]]; then
  rnd_line=$'\n\n'"**RND_DIR (pipeline artifact directory for this project):** \`${rnd_dir}\`"

  # Write the session's originating git root to <base_dir>/.session-git-root so
  # that cwd-changed.sh can detect when the working directory moves to a different
  # repository.  We use a separate file (not .current-session) so the session ID
  # format remains stable.  Silently skip when not inside a git repo.
  base_dir="$(resolve_rnd_dir --base 2>/dev/null || true)"
  if [[ -n "$base_dir" ]]; then
    git_project_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$git_project_root" ]]; then
      printf '%s' "$git_project_root" > "${base_dir}/.session-git-root"
    fi

    # Cache base dir for fast-path lookups in active_session_dir (avoids
    # re-running git+shasum on every subsequent hook invocation).
    cache_dir="${base_dir%/*}"
    printf '%s' "$base_dir" > "${cache_dir}/.active-base-dir" 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# Version mismatch check
# ---------------------------------------------------------------------------

version_warning=""
cached_version=""

if [[ -f "$CACHED_PLUGIN" ]]; then
  cached_version="$(jq_extract "$(< "$CACHED_PLUGIN")" '.version')"
fi

if [[ -n "$cached_version" ]]; then
  git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_root" ]]; then
    for candidate in \
      "${git_root}/plugins/rnd-framework/.claude-plugin/plugin.json" \
      "${git_root}/rnd-framework/.claude-plugin/plugin.json" \
      "${git_root}/.claude-plugin/plugin.json"
    do
      [[ -f "$candidate" ]] || continue
      src_name="$(jq_extract "$(< "$candidate")" '.name')"
      [[ "$src_name" == "rnd-framework" ]] || continue
      src_version="$(jq_extract "$(< "$candidate")" '.version')"
      if [[ -n "$src_version" && "$src_version" != "$cached_version" ]]; then
        version_warning=$'\n\n'"⚠ **Plugin version mismatch:** cached v${cached_version}, source v${src_version}. Run \`/plugin update rnd-framework@rnd-framework-plugins\` to sync. (On v2.1.81+, re-cloning is automatic — if you see this, it likely indicates a bug.)"
      fi
      break
    done
  fi
fi

# ---------------------------------------------------------------------------
# Claude Code version check
# ---------------------------------------------------------------------------

readonly MIN_CLAUDE_VERSION="2.1.97"

cc_version_warning=""
cc_version="$(claude --version 2>/dev/null | awk '{print $1}' || true)"

if [[ -n "$cc_version" ]]; then
  # Compare semver: split on dots, compare numerically left-to-right.
  _ver_gte() {
    local -a a b
    IFS='.' read -ra a <<< "$1"
    IFS='.' read -ra b <<< "$2"
    local i
    for i in 0 1 2; do
      local ai="${a[$i]:-0}" bi="${b[$i]:-0}"
      if (( ai > bi )); then return 0; fi
      if (( ai < bi )); then return 1; fi
    done
    return 0
  }

  if ! _ver_gte "$cc_version" "$MIN_CLAUDE_VERSION"; then
    cc_version_warning=$'\n\n'"⚠ **Claude Code version ${cc_version} is below the minimum recommended v${MIN_CLAUDE_VERSION}.** Some rnd-framework features (subagent cwd isolation, compaction transcript dedup, Stop/SubagentStop hook reliability, session title, statusline refresh) may not work correctly. Run \`claude update\` to upgrade."
  fi
fi

# ---------------------------------------------------------------------------
# Build context and output JSON
# ---------------------------------------------------------------------------

ctx="$(printf '%s' "<EXTREMELY_IMPORTANT>
You have rnd-framework.

**Below is the summary of your 'rnd-framework:using-rnd-framework' skill. For all other skills, use the 'Skill' tool:**

${skill_content}${rnd_line}${version_warning}${cc_version_warning}

</EXTREMELY_IMPORTANT>")"

jq -cn \
  --arg ctx "$ctx" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'

exit 0
