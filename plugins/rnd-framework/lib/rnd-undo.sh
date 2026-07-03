#!/usr/bin/env bash
# rnd-undo.sh — Surgical revert of files written by a single builder task.
#
# Usage:
#   rnd-undo.sh <task_id> [--dry-run]
#
# Reads $RND_DIR/builds/<task_id>-manifest.md, finds the "## Files written"
# section, and for each listed path either reverts to HEAD (if tracked) or
# deletes the file (if newly created since HEAD).
#
# Under --dry-run, prints planned actions to stdout without applying them.
#
# Environment:
#   CLAUDE_PLUGIN_ROOT  Required — used to locate lib/rnd-dir.sh and
#                       lib/audit-event.sh.
#
# Exit codes:
#   0  All operations succeeded (or --dry-run completed).
#   1  Usage error, missing manifest, or a git/rm operation failed.

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

usage() {
  printf 'Usage: rnd-undo.sh <task_id> [--dry-run]\n' >&2
  exit 1
}

die() {
  printf 'rnd-undo: %s\n' "$1" >&2
  exit 1
}

# Parse the "## Files written" section from a manifest file.
# Prints one path per line; strips leading bullets, backticks, and fences.
# Stops at the next "## " heading or EOF.
# Rejects paths starting with `/` (absolute) or containing `..` (traversal):
# the revert path is repo-relative, and a stray absolute / parent-relative path
# would direct `git checkout` / `rm` at locations outside the repo. The
# absolute/`..` rejection below IS the repo-containment guard; revert_file
# trusts that its input has already passed through here.
parse_files_written() {
  local manifest="$1"
  local in_section=0

  while IFS= read -r line; do
    if [[ "$line" == "## Files written" ]]; then
      in_section=1
      continue
    fi

    if [[ $in_section -eq 1 ]]; then
      # Stop at any subsequent ## heading
      if [[ "$line" =~ ^##[[:space:]] ]]; then
        break
      fi

      # Strip leading bullets (- ), backticks, and code-fence markers
      local cleaned
      cleaned="${line#- }"
      cleaned="${cleaned#\`}"
      cleaned="${cleaned%\`}"

      # Skip blank lines, code-fence markers, and comment lines
      [[ -z "$cleaned" ]] && continue
      [[ "$cleaned" == '```' ]] && continue
      [[ "$cleaned" =~ ^[[:space:]]*$ ]] && continue

      # Reject paths that escape the repo root.
      if [[ "$cleaned" == /* ]]; then
        printf 'rnd-undo: refusing absolute path in manifest: %s\n' "$cleaned" >&2
        continue
      fi
      if [[ "$cleaned" == *".."* ]]; then
        printf 'rnd-undo: refusing path with .. traversal in manifest: %s\n' "$cleaned" >&2
        continue
      fi

      printf '%s\n' "$cleaned"
    fi
  done < "$manifest"
}

# Revert or delete a single file path, relative to the repo root.
# Under dry-run, print the intended action instead.
revert_file() {
  local path="$1"
  local dry_run="$2"
  local task_id="$3"

  if git cat-file -e "HEAD:${path}" 2>/dev/null; then
    # File existed at HEAD — revert to HEAD
    if [[ "$dry_run" == "1" ]]; then
      printf 'would checkout %s\n' "$path"
    else
      git checkout HEAD -- "$path" || die "git checkout HEAD -- ${path} failed"
      emit_audit_event "$task_id" "$path"
    fi
  else
    # File is new since HEAD — delete it
    if [[ "$dry_run" == "1" ]]; then
      printf 'would rm %s\n' "$path"
    else
      rm -- "$path" || die "rm ${path} failed"
      emit_audit_event "$task_id" "$path"
    fi
  fi
}

emit_audit_event() {
  local task_id="$1"
  local path="$2"

  local audit_script="${CLAUDE_PLUGIN_ROOT}/lib/audit-event.sh"

  # RND_DIR is resolved in main as an unexported shell variable, so the child
  # process would not inherit it — pass it explicitly (same contract as
  # run-tool.sh's audit-event.sh invocation).
  if [[ -x "$audit_script" ]]; then
    RND_DIR="$RND_DIR" "$audit_script" rnd_undo_applied "$task_id" "$path" || true
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

[[ $# -lt 1 ]] && usage

task_id="$1"
dry_run="0"

# Sanitize task_id before it selects the manifest path: a `/` or `..` would let
# the manifest read escape builds/. The canonical ID shape is M<N>.T<NN>.<slug>;
# this charset rejects any separator while admitting every legitimate id.
if [[ ! "$task_id" =~ ^[A-Za-z0-9._-]+$ ]]; then
  die "invalid task_id '${task_id}': expected characters [A-Za-z0-9._-] only"
fi

if [[ $# -ge 2 && "$2" == "--dry-run" ]]; then
  dry_run="1"
fi

# Resolve RND_DIR via ${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh (no -c: current session only)
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  die "CLAUDE_PLUGIN_ROOT is not set"
fi

rnd_dir_script="${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"
if [[ ! -x "$rnd_dir_script" ]]; then
  die "rnd-dir.sh not found at ${rnd_dir_script}"
fi

RND_DIR="$("$rnd_dir_script")" || die "could not resolve RND_DIR"

manifest="${RND_DIR}/builds/${task_id}-manifest.md"

if [[ ! -f "$manifest" ]]; then
  printf 'rnd-undo: manifest not found: %s\n' "$manifest" >&2
  exit 1
fi

# Collect files from the manifest
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(parse_files_written "$manifest")

if [[ ${#files[@]} -eq 0 ]]; then
  printf 'rnd-undo: no paths found in "## Files written" section of %s\n' "$manifest" >&2
  exit 1
fi

# Revert each file
for f in "${files[@]}"; do
  revert_file "$f" "$dry_run" "$task_id"
done
