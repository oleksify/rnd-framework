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

# Returns 0 when <path> is equal to <root> or nested under <root>/.
path_is_within_root() {
  local path="$1"
  local root="$2"

  [[ -n "$path" && -n "$root" ]] || return 1
  [[ "$path" == "$root" || "$path" == "$root"/* ]]
}

# Prints the configured plugin artifact root.
plugin_artifact_root() {
  local config_dir
  config_dir="$(_resolve_config_dir)"

  printf '%s/.rnd' "$config_dir"
}

# Returns 0 if path is under the configured .rnd/ plugin artifact directory.
is_plugin_artifact_path() {
  local path="$1"
  [[ "$path" == /* ]] || return 1

  local root
  root="$(plugin_artifact_root)"

  path_is_within_root "$path" "$root"
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

# Returns 0 when a command string references the configured .rnd root.
# Matching on the configured root avoids auto-allowing lookalike paths such as
# /tmp/project/.claude-evil/x/.rnd/... while still allowing real artifact paths.
command_references_plugin_artifact_path() {
  local text="$1"
  local root
  root="$(plugin_artifact_root)"

  [[ -n "$text" && -n "$root" ]] || return 1

  case "$text" in
    *"$root"|*"$root"/*|*"$root"\"*|*"$root"\'*|*"$root"\)*|*"$root"\;*|*"$root"\|*|*"$root"\&*|*"$root"\ *)
      return 0
      ;;
  esac

  return 1
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
    # shellcheck disable=SC2034  # Set in caller's scope; sourcing hooks consume all three.
    TOOL_NAME=""
    # shellcheck disable=SC2034  # Set in caller's scope; sourcing hooks consume all three.
    TOOL_INPUT=""
    # shellcheck disable=SC2034  # Set in caller's scope; sourcing hooks consume all three.
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
# shellcheck disable=SC2120  # "$@" forwarded to rnd-dir.sh; session-start.sh/session-end.sh pass --base/--finish.
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
# the caller is a named barrier-restricted agent (rnd-verifier, rnd-polisher).
# Pure; no side effects. Shared by read-gate.sh, glob-grep-gate.sh, and
# bash-gate.sh — the three hooks must agree exactly on the barrier semantics.
#
# The orchestrator runs with an empty agent_type and is the LEGITIMATE consumer
# of briefs/, cleanup/, and self-assessment artifacts (it relays them to the
# user per the orchestration protocol). Empty agent_type is therefore NOT
# barrier-restricted.
#
# Barrier-protected patterns:
#   - "self-assessment.md" — the Builder uncertainty artifact
#     builds/T<id>-self-assessment.md (blocked from Verifier/Polisher).
#   - "self-assessment-properties" — the property-runner output the Builder writes
#     to builds/T<id>-self-assessment-properties.txt (named to inherit barrier
#     protection; see tests/builder-properties.test.sh).
#     Both are matched on their artifact-specific token, NOT the bare
#     "self-assessment" substring, so legitimately-named SOURCE files (e.g.
#     hooks/self-assessment-producer.sh and its test — "self-assessment-producer")
#     are not false-positives. The tokens still catch absolute and relative
#     references to the real artifacts.
#   - ".rnd/.../briefs/" — user-facing narrative artifacts that may echo Builder
#     reasoning. The `.rnd/` artifact-root anchor distinguishes the artifact
#     tree from same-named directories elsewhere (e.g. project source).
#   - ".rnd/.../cleanup/" — per-task cleanup reports (barrier-protected from
#     Verifier; mirrors /briefs/ semantics).
#
# The `.rnd/` anchor is load-bearing: project source trees may contain their
# own `briefs/` or `cleanup/` directories (e.g. application-level cleanup
# scripts, design briefs). Without the anchor those legitimate project paths
# would be mistaken for artifact-tree reports and blocked from agents.
is_barrier_violation() {
  local text="$1"
  local agent_type="${2:-}"
  local text_lower agent_lower
  text_lower="$(_lower "$text")"
  local has_pattern=0
  if [[ "$text_lower" == *"self-assessment.md"* || "$text_lower" == *"self-assessment-properties"* ]]; then
    has_pattern=1
  elif [[ "$text_lower" =~ \.rnd/.*briefs/ ]]; then
    has_pattern=1
  elif [[ "$text_lower" =~ \.rnd/.*cleanup/ ]]; then
    has_pattern=1
  fi
  [[ "$has_pattern" -eq 1 ]] || return 1
  agent_lower="$(_lower "$agent_type")"
  [[ "$agent_lower" == *"verifier"* || "$agent_lower" == *"polisher"* ]]
}

# Returns 0 iff <file_path> points at one of the four canonical plan artifacts
# at the active session root AND a re-plan-in-progress marker is present AND
# the caller is the freshly-spawned Planner. Otherwise returns 1 (no
# violation). Pure-ish: probes the filesystem for the marker file but has no
# side effects.
#
# Why this exists (defense-in-depth around the re-plan flow):
#
#   The orchestrator archives the prior plan under prior-plans/replan-<k>/
#   and writes a marker at $session_dir/.replan-in-progress before spawning a
#   fresh Planner. The intent is that the new Planner reasons from the
#   protocol-style brief alone — not from the artifacts it is about to
#   overwrite. The spawn-prompt construction omits the prior content, but
#   prompt-omission alone is fragile: a future code path may forget to omit,
#   or the Planner may try to Read the canonical paths directly. This
#   predicate is the hook-level safety net.
#
#   Design rationale:
#     - Prompt-omission fragility: barrier blocks Read regardless of whether
#       the orchestrator omitted prior-plan content from the spawn prompt.
#     - Agent-type drift: matched on substring "planner" so any future
#       planner variant (rnd-planner, rnd-planner-fast, …) is caught, while
#       rnd-replan-differ (contains "rep" but not "planner") is NOT caught —
#       the differ must still be able to compare archives to drafts.
#     - Over-blocking guard: the orchestrator (empty agent_type) and the
#       differ are explicitly excluded so they can do their jobs reading both
#       archived and canonical paths.
#     - Marker as a file, not an env var: probed at hook-invocation time,
#       survives subprocess boundaries cleanly where env vars would be lost.
#
#   The barrier targets Read/Glob/Grep only. write-gate.sh is intentionally
#   NOT wired to this predicate — the Planner MUST be able to Write the new
#   canonical artifacts to replace the archived ones.
#
#   Archived paths under prior-plans/replan-*/ are out of scope: the
#   barrier protects only the canonical session-root paths. A planner can
#   still cross-reference an archive if it really wants — the spawn-prompt
#   guidance discourages that, but the hook does not enforce it.
is_replan_artifact_violation() {
  local file_path="$1"
  local agent_type="${2:-}"

  [[ -n "$file_path" ]] || return 1

  local agent_lower
  agent_lower="$(_lower "$agent_type")"
  [[ "$agent_lower" == *"planner"* ]] || return 1

  local session_dir
  session_dir="$(active_session_dir 2>/dev/null)" || return 1

  [[ -f "${session_dir}/.replan-in-progress" ]] || return 1

  local abs
  abs="$(normalize_artifact_path "$file_path")"
  # Collapse repeated slashes (e.g. from path/pattern smuggling concatenation
  # in glob-grep-gate.sh: "<session_dir>" + "/protocol.md" → "<dir>//protocol.md").
  # macOS realpath lacks -e so normalize_artifact_path is a no-op for absolute
  # inputs that don't exist on disk; tr -s ensures the matcher is robust
  # independently of that. Bash 3.2's pattern-replacement syntax mishandles
  # slash escapes, so tr is the safer primitive.
  abs="$(printf '%s' "$abs" | tr -s /)"

  case "$abs" in
    "${session_dir}/protocol.md") return 0 ;;
    "${session_dir}/validation-contract.md") return 0 ;;
    "${session_dir}/features.json") return 0 ;;
    "${session_dir}/AGENTS.md") return 0 ;;
  esac

  return 1
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
    # Catches both .md and the wave-N-verdict-map.json — the JSON appears first.
    printf 'Verifying'
  elif compgen -G "${dir}/builds/"*.md > /dev/null 2>&1; then
    printf 'Building'
  elif [[ -f "${dir}/protocol.md" ]] || [[ -f "${dir}/plan.md" ]]; then
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
# Path-identity helpers — pure (input path → output string, no side effects)
# ---------------------------------------------------------------------------

# Normalizes an artifact file_path to absolute form (the FM1 guard).
# An already-absolute path is returned unchanged. A relative path is resolved
# via `realpath -e`; if resolution fails (path does not exist on disk), the
# original relative path is returned so the caller can still fall back to it.
# Pure-ish: one realpath probe, deterministic for a given filesystem state.
# Shared by the path-driven producer hooks so the relative→absolute fallback
# lives in exactly one place.
normalize_artifact_path() {
  local path="$1"

  if [[ "$path" == /* ]]; then
    printf '%s' "$path"
    return 0
  fi

  local resolved
  resolved="$(realpath -e "$path" 2>/dev/null || true)"

  if [[ -n "$resolved" ]]; then
    printf '%s' "$resolved"
    return 0
  fi

  printf '%s' "$path"
}

# Extracts the session_id from an artifact file_path by reading the path
# component immediately after the first /sessions/ segment.
# Works for both branch-partitioned and legacy path layouts.
# Prints the session id, or empty string when no /sessions/ component exists.
session_id_from_path() {
  local path="$1"
  local after_sessions

  case "$path" in
    */sessions/*)
      after_sessions="${path#*/sessions/}"
      printf '%s' "${after_sessions%%/*}"
      ;;
    *)
      printf ''
      ;;
  esac
}

# Derives the slug-root calibration.jsonl path from an artifact file_path.
# The slug is the path component immediately following /.rnd/ (same as what
# rnd-dir.sh --calibration returns: <config>/.rnd/<slug>/calibration.jsonl).
# Returns empty when the path contains no /.rnd/ segment.
calib_path_from_artifact() {
  local path="$1"
  local prefix after_rnd slug

  case "$path" in
    */.rnd/*)
      prefix="${path%%/.rnd/*}"
      after_rnd="${path#*/.rnd/}"
      slug="${after_rnd%%/*}"
      printf '%s/.rnd/%s/calibration.jsonl' "$prefix" "$slug"
      ;;
    *)
      printf ''
      ;;
  esac
}

# Emits one tab-separated assertion line when the id is non-empty; no-op
# otherwise. Module-private helper for parse_contract_assertions (defined at
# top level so it is not redefined on every parse call).
__emit_assertion_line() {
  [[ -n "$1" ]] || return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

# Walks every ### M<N>.<area>.<slug> assertion heading in contract_content and
# emits one tab-separated line per assertion:
#   <assertion_id>\t<shape>\t<confidence>
# Shape and Confidence fields are lowercased and trailing-space-trimmed.
# Missing fields are emitted as empty strings (tab still present).
# Output contract: consumers split on \t and take fields 1, 2, 3.
parse_contract_assertions() {
  local contract_content="$1"
  local heading_re='^###[[:space:]]+(M[0-9]+\.[a-z0-9-]+\.[a-z0-9-]+)([[:space:]]|$)'
  local current_id="" current_shape="" current_confidence=""

  while IFS= read -r line; do
    if [[ "$line" =~ $heading_re ]]; then
      __emit_assertion_line "$current_id" "$current_shape" "$current_confidence"

      current_id="${BASH_REMATCH[1]}"
      current_shape=""
      current_confidence=""
      continue
    fi

    if [[ "$line" =~ ^## ]]; then
      __emit_assertion_line "$current_id" "$current_shape" "$current_confidence"

      current_id=""
      current_shape=""
      current_confidence=""
      continue
    fi

    if [[ -n "$current_id" ]]; then
      if [[ "$line" =~ ^[[:space:]]*Shape:[[:space:]]*(.*)$ ]]; then
        current_shape="$(_lower "${BASH_REMATCH[1]}")"
        current_shape="${current_shape%"${current_shape##*[![:space:]]}"}"
      elif [[ "$line" =~ ^[[:space:]]*Confidence:[[:space:]]*(.*)$ ]]; then
        current_confidence="$(_lower "${BASH_REMATCH[1]}")"
        current_confidence="${current_confidence%"${current_confidence##*[![:space:]]}"}"
      fi
    fi
  done <<< "$contract_content"

  __emit_assertion_line "$current_id" "$current_shape" "$current_confidence"
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
