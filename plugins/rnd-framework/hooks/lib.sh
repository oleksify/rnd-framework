#!/usr/bin/env bash
# hooks/lib.sh — Shared bash utilities for rnd-framework hooks.
# Source from any hook: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# ---------------------------------------------------------------------------
# String utilities (bash 3.2 compatible)
# ---------------------------------------------------------------------------

# Lowercase a string. Uses tr instead of ${var,,} for macOS stock bash (3.2) compat.
_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# ---------------------------------------------------------------------------
# Path utilities
# ---------------------------------------------------------------------------

# Returns 0 if path is under the .rnd/ plugin artifact directory
# within a .claude config directory.
is_plugin_artifact_path() {
  local path="$1"
  [[ "$path" == /* ]] || return 1
  [[ "$path" =~ \.claude[^/]*/.*\.rnd/ ]]
}

# Backward-compatible alias.
is_rnd_path() { is_plugin_artifact_path "$1"; }

# Returns 0 if path contains plugins/cache/ under a .claude config directory.
is_plugin_cache_path() {
  local path="$1"
  [[ "$path" == /* ]] || return 1
  [[ "$path" =~ \.claude[^/]*/.*plugins/cache/ ]]
}

# Returns 0 if path contains learnings/ under a .claude config directory.
is_learnings_path() {
  local path="$1"
  [[ "$path" == /* ]] || return 1
  [[ "$path" =~ \.claude[^/]*/.*learnings/ ]]
}

# Returns 0 if the file has a recognised source-code extension.
is_code_file() {
  local path="$1"
  local ext="${path##*.}"
  ext="$(_lower "$ext")"
  case "$ext" in
    ts|tsx|js|jsx|mjs|cjs|\
    py|rb|go|rs|java|\
    c|cpp|h|hpp|cs|\
    swift|kt|scala|\
    sh|bash|zsh|fish|\
    lua|php|vue|svelte|\
    ex|exs|\
    lean|kk|ml|mli)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Hook response output
# ---------------------------------------------------------------------------

# Outputs the PreToolUse allow JSON to stdout.
allow_json() {
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
}

# Outputs an advisory JSON to stdout via top-level systemMessage.
# Uses systemMessage (not hookSpecificOutput.additionalContext) because
# additionalContext requires hookEventName and is only valid for
# PostToolUse/UserPromptSubmit — not PreToolUse or other event types.
advisory_json() {
  system_message_json "$1"
}

# Outputs a system message JSON to stdout. Creates a system-level message in the transcript.
# More prominent than advisory_json — use for state restoration and critical context.
system_message_json() {
  local msg="$1"
  printf '{"systemMessage":%s}\n' "$(printf '%s' "$msg" | jq -Rs .)"
}

# Writes message to stderr and exits 2. Blocks a hook operation.
block_msg() {
  local msg="$1"
  printf '%s\n' "$msg" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# Stdin parsing
# ---------------------------------------------------------------------------

# Reads all of stdin into a variable, then extracts TOOL_NAME, TOOL_INPUT,
# and AGENT_TYPE using a single jq call. Sets those variables in the caller's scope.
# On malformed input, sets all to empty strings.
parse_input() {
  local raw parsed
  raw="$(cat)"
  parsed="$(printf '%s' "$raw" | jq -r '
    [(.tool_name // ""), (.tool_input // {} | tojson), (.agent_type // "")]
    | join("\t")' 2>/dev/null || true)"
  if [[ -n "$parsed" ]]; then
    IFS=$'\t' read -r TOOL_NAME TOOL_INPUT AGENT_TYPE <<< "$parsed"
  else
    TOOL_NAME=""
    TOOL_INPUT=""
    AGENT_TYPE=""
  fi
}

# Extracts file_path from a tool_input JSON string.
# Usage: fp="$(extract_file_path "$TOOL_INPUT")"
extract_file_path() {
  local tool_input="$1"
  printf '%s' "$tool_input" | jq -r '.file_path // ""' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# RND directory resolution
# ---------------------------------------------------------------------------

# Regex for valid session IDs (YYYYMMDD-HHMMSS-xxxx) as written by rnd-dir.sh.
# Guard prevents a re-declaration error when lib.sh is sourced more than once.
[[ -n "${SESSION_ID_RE+x}" ]] || readonly SESSION_ID_RE='^[0-9]{8}-[0-9]{6}-[0-9a-f]{4,8}$'

# Resolves the Claude config directory from environment variables.
# Mirrors the precedence in plugin-dir-base.sh — keep them in sync.
_resolve_config_dir() {
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    local dir="${CLAUDE_PLUGIN_ROOT%%/plugins/cache/*}"
    [[ "$dir" != "$CLAUDE_PLUGIN_ROOT" ]] && { printf '%s' "$dir"; return 0; }
    printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; return 0
  fi
  [[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && { printf '%s' "$CLAUDE_CONFIG_DIR"; return 0; }
  printf '%s' "$HOME/.claude"
}

# Calls rnd-dir.sh relative to the lib.sh location and prints the path.
# Accepts optional flags (e.g. -c, --base) passed through to rnd-dir.sh.
# Prints nothing and returns 1 on failure.
resolve_rnd_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local rnd_script="${script_dir}/../lib/rnd-dir.sh"
  if [[ ! -x "$rnd_script" ]]; then
    return 1
  fi
  local result
  result="$("$rnd_script" "$@" 2>/dev/null)" || return 1
  [[ -n "$result" ]] && printf '%s' "$result" || return 1
}

# Returns the active session directory path when it exists and contains /sessions/.
# Prints nothing and returns 1 otherwise.
# Uses a process-level cache and a fast-path that reads a cached base-dir file
# written by session-start.sh, avoiding the expensive git+shasum computation
# (~15ms) on every hook invocation.
_ACTIVE_SESSION_CACHE=""
_ACTIVE_SESSION_RESOLVED=0
active_session_dir() {
  if [[ "$_ACTIVE_SESSION_RESOLVED" -eq 1 ]]; then
    [[ -n "$_ACTIVE_SESSION_CACHE" ]] || return 1
    printf '%s' "$_ACTIVE_SESSION_CACHE"
    return 0
  fi
  _ACTIVE_SESSION_RESOLVED=1

  local config_dir
  config_dir="$(_resolve_config_dir)"

  local cache_file="${config_dir}/.rnd/.active-base-dir"
  if [[ -f "$cache_file" ]]; then
    local base_dir
    base_dir="$(< "$cache_file")"
    if [[ -n "$base_dir" && -f "${base_dir}/.current-session" ]]; then
      local session_id
      session_id="$(< "${base_dir}/.current-session")"
      [[ "$session_id" =~ $SESSION_ID_RE ]] || return 1
      local dir="${base_dir}/sessions/${session_id}"
      if [[ -d "$dir" ]]; then
        _ACTIVE_SESSION_CACHE="$dir"
        printf '%s' "$dir"
        return 0
      fi
    fi
  fi

  # Slow path: fall back to resolve_rnd_dir (git+shasum)
  local dir
  dir="$(resolve_rnd_dir)" || return 1
  [[ "$dir" == */sessions/* ]] || return 1
  [[ -d "$dir" ]] || return 1
  _ACTIVE_SESSION_CACHE="$dir"
  printf '%s' "$dir"
}

# ---------------------------------------------------------------------------
# Information barrier
# ---------------------------------------------------------------------------

# Returns 0 iff the lowered <text> contains a barrier-protected pattern AND
# the caller has no agent_type OR has one that names a verifier. Pure; no
# side effects. Shared by read-gate.sh, glob-grep-gate.sh, and bash-gate.sh —
# the three hooks must agree exactly on the barrier semantics.
#
# Barrier-protected patterns:
#   - "self-assessment" — Builder uncertainty records (blocked from Verifier)
#   - "/briefs/" — user-facing narrative artifacts that may echo Builder reasoning
#     (matched as a path segment with slashes so the bare word "brief" in a
#     grep pattern is not flagged)
#   - "/cleanup/" — per-task cleanup reports (barrier-protected from Verifier;
#     mirrors /briefs/ semantics)
is_barrier_violation() {
  local text="$1"
  local agent_type="${2:-}"
  local text_lower agent_lower
  text_lower="$(_lower "$text")"
  local has_pattern=0
  if [[ "$text_lower" == *"self-assessment"* ]]; then
    has_pattern=1
  elif [[ "$text_lower" == *"/briefs/"* ]]; then
    has_pattern=1
  elif [[ "$text_lower" == *"/cleanup/"* ]]; then
    # /cleanup/ — barrier-protected cleanup-report artifacts (mirrors /briefs/)
    has_pattern=1
  fi
  [[ "$has_pattern" -eq 1 ]] || return 1
  agent_lower="$(_lower "$agent_type")"
  [[ -z "$agent_lower" || "$agent_lower" == *"verifier"* || "$agent_lower" == *"proof-gate"* || "$agent_lower" == *"polisher"* ]]
}

# ---------------------------------------------------------------------------
# Pipeline phase detection
# ---------------------------------------------------------------------------

# Echoes one of Idle|Planning|Building|Verifying|Integrating based on which
# artifact directories exist under <session_dir>. Empty/missing dir → Idle.
# Shared by statusline.sh and session-title.sh.
detect_pipeline_phase() {
  local dir="${1:-}"
  if [[ -z "$dir" ]] || [[ ! -d "$dir" ]]; then
    printf 'Idle'
    return 0
  fi
  if compgen -G "${dir}/integration/"*.md > /dev/null 2>&1; then
    printf 'Integrating'
  elif [[ -n "$(ls -A "${dir}/verifications/" 2>/dev/null)" ]]; then
    printf 'Verifying'
  elif compgen -G "${dir}/builds/"*.md > /dev/null 2>&1; then
    printf 'Building'
  elif [[ -f "${dir}/plan.md" ]]; then
    printf 'Planning'
  else
    printf 'Idle'
  fi
}

# ---------------------------------------------------------------------------
# Timestamps
# ---------------------------------------------------------------------------

# Outputs an ISO 8601 UTC timestamp without milliseconds (e.g. 2025-03-22T09:10:11Z).
iso_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# ---------------------------------------------------------------------------
# Markdown section parsing — shared by SubagentStop gate hooks.
# ---------------------------------------------------------------------------

# Extracts content between `## <heading>` and the next `##` heading.
# Heading match is anchored: matches `## <heading>` followed by either end-of-line
# or whitespace — `## Verdict` does not match `## Verdicts`.
# Args: heading, content.
extract_section() {
  local heading="$1"
  local content="$2"
  local section_content=""
  local in_section=0
  local heading_re="^##[[:space:]]+${heading}([[:space:]]|\$)"

  while IFS= read -r line; do
    if [[ "$line" =~ $heading_re ]]; then
      in_section=1
      continue
    fi

    if [[ "$in_section" -eq 1 ]]; then
      if [[ "$line" =~ ^## ]]; then
        break
      fi
      section_content="${section_content}${line}
"
    fi
  done <<< "$content"

  printf '%s' "$section_content"
}

# Returns 0 (trivial) when every non-blank line in section_content matches one of
# the lowercase denylist terms after bullet-marker and `label: ` prefix stripping.
# Returns 1 when substantive content is found, when section is empty, or when no
# denylist terms are given.
# Args: section_content, then one or more lowercase denylist terms.
is_trivial_section() {
  local section_content="$1"
  shift
  local trivial_only=1
  local has_any_content=0
  local line line_stripped stripped sub_value term matched

  while IFS= read -r line; do
    line_stripped="${line#"${line%%[! ]*}"}"
    if [[ -z "$line_stripped" ]]; then
      continue
    fi

    has_any_content=1

    stripped="${line_stripped#-}"
    stripped="${stripped#\*}"
    stripped="${stripped# }"

    sub_value="$(_lower "$stripped")"
    if [[ "$sub_value" == *": "* ]]; then
      sub_value="${sub_value#*: }"
    fi

    matched=0
    for term in "$@"; do
      if [[ "$sub_value" == "$term" ]]; then
        matched=1
        break
      fi
    done

    if [[ "$matched" -eq 0 ]]; then
      trivial_only=0
      break
    fi
  done <<< "$section_content"

  if [[ "$has_any_content" -eq 1 && "$trivial_only" -eq 1 ]]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Bash output cache
# ---------------------------------------------------------------------------
# Shared by post-dispatch.sh (writer) and bash-gate.sh (advisory). Both must
# normalize and hash a command identically — the helpers below are the
# single source of truth.

# Collapses runs of whitespace to a single space and trims leading/trailing
# whitespace. Stable across cosmetic command variations (extra spaces, tabs).
_normalize_cmd() {
  local cmd="$1"
  cmd="$(printf '%s' "$cmd" | tr -s '[:space:]' ' ')"
  cmd="${cmd# }"
  cmd="${cmd% }"
  printf '%s' "$cmd"
}

# Returns a 16-char sha-256 hex prefix of the normalized command. Empty input
# returns empty (callers should guard).
cmd_hash() {
  local cmd="$1"
  [[ -n "$cmd" ]] || return 0
  local norm
  norm="$(_normalize_cmd "$cmd")"
  printf '%s' "$norm" | shasum -a 256 2>/dev/null | cut -c1-16
}

# Returns the path to the bash output cache directory under the active session.
# Does NOT create it — the writer is responsible for mkdir -p when needed; the
# reader (bash-gate) only checks for hits and should never create the dir.
# Returns empty and exit 1 when no active session.
bash_cache_dir() {
  local session_dir
  session_dir="$(active_session_dir 2>/dev/null)" || return 1
  printf '%s' "${session_dir}/.bash-cache"
}

# ---------------------------------------------------------------------------
# FP utilities
# ---------------------------------------------------------------------------

# Extracts a jq field from JSON; prints the value or empty string; always returns 0.
jq_extract() {
  local json="$1"
  local field="$2"
  local result
  result="$(printf '%s' "$json" | jq -r "${field} // empty" 2>/dev/null)" || true
  printf '%s' "$result"
  return 0
}

# Returns 0 when value is non-empty, 1 when empty; prints optional message to stderr on empty.
# Usage: guard_nonempty "$val" "description" || return 0
guard_nonempty() {
  local value="$1"
  local message="${2:-}"
  if [[ -n "$value" ]]; then
    return 0
  fi
  [[ -z "$message" ]] || printf '%s\n' "$message" >&2
  return 1
}

# Reads stdin, removes YAML frontmatter (lines between first --- and second --- inclusive), prints remainder.
strip_frontmatter() {
  awk '
    /^---$/ && !seen_open { seen_open=1; next }
    /^---$/ && seen_open && !seen_close { seen_close=1; next }
    seen_close || !seen_open { print }
  '
}
