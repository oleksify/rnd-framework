#!/usr/bin/env bash
# run-tool.sh — Evidence pack writer for tool invocations.
#
# Usage:
#   run-tool.sh [--task-id <id>] -- <command> [args...]
#
# When RND_EVIDENCE_PACK=1 and RND_DIR is set, captures stdout/stderr,
# hashes tracked input files, and writes a manifest.json to:
#   $RND_DIR/evidence/<task-id>/
#
# When RND_EVIDENCE_PACK is unset or != "1", executes the command directly
# (transparent passthrough).
#
# Environment:
#   RND_EVIDENCE_PACK  Set to "1" to enable pack writing.
#   RND_DIR            Path to the active RND session directory.
#   RND_TASK_ID        Task ID for the evidence subdirectory (overridden by --task-id).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Skip-list patterns (directory names/segments to exclude from inputs) ---
SKIP_LIST="node_modules .rnd _build deps .venv target dist"

# --- Usage ---
usage() {
  printf 'Usage: run-tool.sh [--task-id <id>] -- <command> [args...]\n'
  printf '\n'
  printf 'Options:\n'
  printf '  --task-id <id>   Evidence subdirectory name (default: $RND_TASK_ID or "default")\n'
  printf '  --help           Show this help\n'
  printf '\n'
  printf 'Environment:\n'
  printf '  RND_EVIDENCE_PACK  Set to "1" to enable evidence pack writing\n'
  printf '  RND_DIR            Path to the active RND session directory\n'
  printf '  RND_TASK_ID        Task ID (overridden by --task-id)\n'
}

# --- Argument parsing ---
task_id="${RND_TASK_ID:-task-$(date -u +%Y%m%dT%H%M%SZ)}"
cmd_args=()

_validate_task_id() {
  local id="$1"

  if [[ ! "$id" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'run-tool.sh: invalid --task-id %q (must match [A-Za-z0-9._-]+)\n' "$id" >&2
    exit 1
  fi
}

_validate_task_id "$task_id"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --task-id)
      task_id="$2"
      _validate_task_id "$task_id"
      shift 2
      ;;
    --)
      shift
      cmd_args=("$@")
      break
      ;;
    *)
      cmd_args=("$@")
      break
      ;;
  esac
done

if [[ ${#cmd_args[@]} -eq 0 ]]; then
  usage
  exit 0
fi

# --- Passthrough mode ---
if [[ "${RND_EVIDENCE_PACK:-}" != "1" ]]; then
  exec "${cmd_args[@]}"
fi

# --- Evidence pack mode ---
if [[ -z "${RND_DIR:-}" ]]; then
  printf 'run-tool.sh: RND_EVIDENCE_PACK=1 but RND_DIR is not set; executing without pack\n' >&2
  exec "${cmd_args[@]}"
fi

# --- Load and merge tools.json (plugin default + optional project override) ---
plugin_tools_json="${SCRIPT_DIR}/tools.json"
project_tools_json="${RND_DIR}/tools.json"

merged_tools_json="{}"
if [[ -f "$plugin_tools_json" ]]; then
  merged_tools_json="$(cat "$plugin_tools_json")"
fi

if [[ -f "$project_tools_json" ]]; then
  merged_tools_json="$(printf '%s\n%s' "$merged_tools_json" "$(cat "$project_tools_json")" | jq -s '.[0] * .[1]')"
fi

# Inject structured_flags for the tool if defined
tool_name="${cmd_args[0]}"
tool_base="$(basename "$tool_name")"

structured_flags_json="$(printf '%s' "$merged_tools_json" | jq -r --arg t "$tool_base" '.[$t].structured_flags // empty' 2>/dev/null || true)"

if [[ -n "$structured_flags_json" ]]; then
  # Build extra flags array (skip {output} placeholder entries — they require a path arg)
  extra_flags=()
  while IFS= read -r flag; do
    # Skip flags with {output} placeholder (caller must supply the path)
    case "$flag" in
      *"{output}"*) continue ;;
      *) extra_flags+=("$flag") ;;
    esac
  done < <(printf '%s' "$structured_flags_json" | jq -r '.[]')

  # Reconstruct cmd_args with structured flags appended (before any existing -- separator)
  cmd_args=("${cmd_args[@]}" "${extra_flags[@]}")
fi

# Load relevant_globs for the tool — narrows inputs[] to files the tool plausibly reads.
# When unset/empty, falls back to all tracked files (conservative correctness over savings).
TOOL_GLOBS=()
while IFS= read -r glob; do
  [[ -n "$glob" ]] && TOOL_GLOBS+=("$glob")
done < <(printf '%s' "$merged_tools_json" | jq -r --arg t "$tool_base" '.[$t].relevant_globs // [] | .[]' 2>/dev/null || true)

# Prepare evidence directory
evidence_dir="${RND_DIR}/evidence/${task_id}"
mkdir -p "$evidence_dir"

# Timestamps
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Capture stdout and stderr to evidence dir
stdout_path="${evidence_dir}/stdout.txt"
stderr_path="${evidence_dir}/stderr.txt"

exit_code=0
"${cmd_args[@]}" >"$stdout_path" 2>"$stderr_path" || exit_code=$?

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Input hashing ---

_is_skip_path() {
  local path="$1"
  for seg in $SKIP_LIST; do
    case "$path" in
      "${seg}"|"${seg}/"*|*"/${seg}/"*|*"/${seg}")
        return 0
        ;;
    esac
  done
  return 1
}

# Returns 0 if the path matches any pattern in TOOL_GLOBS, 1 otherwise.
# When TOOL_GLOBS is empty, returns 0 (no narrowing — include everything).
# Patterns are bash glob patterns matched against either the full path or the basename.
# A pattern with no '/' matches against the basename (e.g. '*.py' matches 'src/foo.py').
# A pattern with '/' matches against the full relative path.
_path_matches_globs() {
  local path="$1"
  if [[ ${#TOOL_GLOBS[@]} -eq 0 ]]; then
    return 0
  fi
  local glob basename
  basename="${path##*/}"
  # shellcheck disable=SC2053  # Unquoted RHS is intentional: glob patterns must expand for matching.
  for glob in "${TOOL_GLOBS[@]}"; do
    case "$glob" in
      */*) [[ "$path" == $glob ]] && return 0 ;;
      *)   [[ "$basename" == $glob ]] && return 0 ;;
    esac
  done
  return 1
}

_hash_file() {
  local path="$1"
  local hash=""
  hash="$(shasum -a 256 "$path" 2>/dev/null | cut -c1-64 || true)"
  printf '%s' "$hash"
}

# Collect tracked + modified files from project root
# Get project root (git root or cwd)
project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Accumulate path<TAB>hash records — tab is safe because git paths never contain tabs.
# The single jq call after the loop converts these records to the JSON array.
inputs_buf=""

while IFS= read -r -d '' filepath; do
  abs_path="${project_root}/${filepath}"

  if _is_skip_path "$filepath"; then
    continue
  fi

  if ! _path_matches_globs "$filepath"; then
    continue
  fi

  if [[ ! -f "$abs_path" ]]; then
    continue
  fi

  hash="$(_hash_file "$abs_path")"

  if [[ -z "$hash" ]]; then
    continue
  fi

  inputs_buf="${inputs_buf}${filepath}	${hash}
"
done < <(git -C "$project_root" ls-files -z 2>/dev/null || true)

# Build the inputs JSON array in a single jq pass from the accumulated records.
inputs_json="$(printf '%s' "$inputs_buf" | jq -R -s '[split("\n")[] | select(length > 0) | split("\t") | {path: .[0], sha256: .[1]}]')"

# Only tracked files are included by default.

# --- Write manifest.json ---
manifest_path="${evidence_dir}/manifest.json"

# Build command_argv as JSON array
cmd_argv_json="$(printf '%s\n' "${cmd_args[@]}" | jq -R . | jq -s .)"

jq -n \
  --arg tool "${cmd_args[0]}" \
  --argjson command_argv "$cmd_argv_json" \
  --arg cwd "$(pwd)" \
  --arg started_at "$started_at" \
  --arg finished_at "$finished_at" \
  --argjson exit_code "$exit_code" \
  --arg stdout_path "$stdout_path" \
  --arg stderr_path "$stderr_path" \
  --argjson inputs "$inputs_json" \
  '{
    tool: $tool,
    command_argv: $command_argv,
    cwd: $cwd,
    started_at: $started_at,
    finished_at: $finished_at,
    exit_code: $exit_code,
    stdout_path: $stdout_path,
    stderr_path: $stderr_path,
    inputs: $inputs
  }' > "$manifest_path"

# Emit audit event to $RND_DIR/audit.jsonl via the shared helper
# (single source of truth for audit-event JSON format).
RND_DIR="$RND_DIR" "${SCRIPT_DIR}/audit-event.sh" tool_run_fresh "$task_id" "${cmd_args[0]}" 2>/dev/null || true

# Exit with the wrapped command's exit code
exit "$exit_code"
