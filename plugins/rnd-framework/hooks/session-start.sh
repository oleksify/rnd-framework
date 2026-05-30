#!/usr/bin/env bash
# hooks/session-start.sh — SessionStart hook for rnd-framework plugin.
# Injects full RND context when a pipeline session is active; emits a one-line
# stub otherwise so idle sessions pay minimal context cost.
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

  if [[ -n "$trim_line" && "$trim_line" -ge 2 ]]; then
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
# Compute the active session dir ONCE — used for both the context gate and
# the session title. The active gate requires both a non-empty path and that
# the directory actually exists on disk (guards against stale .current-session
# pointers).
# ---------------------------------------------------------------------------

active_dir="$(active_session_dir 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Cache the branch base dir for session-state files (.session-git-root and
# .active-base-dir). resolve_rnd_dir --base is a pure path computation that
# never creates directories, so mkdir -p must precede the writes. The cache
# writes run unconditionally in both the active and inactive branches because
# they are session-state maintenance, not pipeline-context logic.
# ---------------------------------------------------------------------------

base_dir="$(resolve_rnd_dir --base 2>/dev/null || true)"
if [[ -n "$base_dir" ]]; then
  # mkdir -p must come first: --base never creates dirs.
  mkdir -p "$base_dir"

  git_project_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_project_root" ]]; then
    printf '%s' "$git_project_root" > "${base_dir}/.session-git-root"
  fi

  # Cache file lives at <.rnd-root>/.active-base-dir — hardcoded in lib.sh::active_session_dir.
  # Strip /<slug>/branches/<branch> to reach <config>/.rnd.
  if [[ "$base_dir" == */branches/* ]]; then
    rnd_root="${base_dir%%/branches/*}"   # <config>/.rnd/<slug>
    rnd_root="${rnd_root%/*}"             # <config>/.rnd
  else
    rnd_root="${base_dir%/*}"             # fallback: legacy un-partitioned <slug> → <config>/.rnd
  fi
  printf '%s' "$base_dir" > "${rnd_root}/.active-base-dir" 2>/dev/null || true
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
        version_warning=$'\n\n'"⚠ **Plugin version mismatch:** cached v${cached_version}, source v${src_version}. Run \`/plugin update rnd-framework@rnd-framework-plugins\` to sync."
      fi
      break
    done
  fi
fi

# ---------------------------------------------------------------------------
# Claude Code version check
# ---------------------------------------------------------------------------

readonly MIN_CLAUDE_VERSION="2.1.139"

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
    cc_version_warning=$'\n\n'"⚠ **Claude Code version ${cc_version} is below the minimum recommended v${MIN_CLAUDE_VERSION}.** Some rnd-framework features (subagent cwd isolation, compaction transcript dedup, Stop/SubagentStop hook reliability, session title, statusline refresh, subagent stall timeout, Opus-4.7 1M-context fix, agent-type hooks for non-Stop events, SendMessage subagent cwd restore) may not work correctly. Run \`claude update\` to upgrade."
  fi
fi

# ---------------------------------------------------------------------------
# Build context: full block when a pipeline session is active; one-line stub
# otherwise. Version warnings are appended in both branches.
# ---------------------------------------------------------------------------

if [[ -n "$active_dir" && -d "$active_dir" ]]; then
  rnd_line=$'\n\n'"**RND_DIR (pipeline artifact directory for this project):** \`${active_dir}\`"

  ctx="$(printf '%s' "<EXTREMELY_IMPORTANT>
You have rnd-framework.

**Below is the summary of your 'rnd-framework:using-rnd-framework' skill. For all other skills, use the 'Skill' tool:**

${skill_content}${rnd_line}${version_warning}${cc_version_warning}

</EXTREMELY_IMPORTANT>")"
else
  ctx="$(printf '%s' "<system-reminder>rnd-framework is active. Use /rnd-framework:rnd-start to begin a pipeline. The using-rnd-framework skill is available via the Skill tool.${version_warning}${cc_version_warning}</system-reminder>")"
fi

# ---------------------------------------------------------------------------
# Session title — phase-aware, mirroring session-title.sh's UserPromptSubmit
# computation so the title is correct immediately on startup/resume (not only
# after the first prompt submission). Honored on Claude Code ≥ 2.1.152;
# older versions silently ignore the field.
# ---------------------------------------------------------------------------

phase_for_title="$(detect_pipeline_phase "$active_dir" 2>/dev/null || echo Idle)"
project_for_title="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"

if [[ "$phase_for_title" == "Idle" ]]; then
  session_title="RND: ${project_for_title}"
else
  session_title="RND: ${phase_for_title} | ${project_for_title}"
fi

jq -cn \
  --arg ctx "$ctx" \
  --arg title "$session_title" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx,sessionTitle:$title}}'

exit 0
