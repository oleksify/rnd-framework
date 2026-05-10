#!/usr/bin/env bash
# hooks/post-dispatch.sh — Unified PostToolUse hook.
#
# Merged from post-tool-use.sh + observation-mask.sh into a single dispatcher.
# Fast-path: exits immediately when no active RND session.
#
# Responsibilities:
#   1. Audit logging (Write/Edit) — appends JSONL to $RND_DIR/audit.jsonl
#   2. Observation mask (Bash) — advises when output exceeds threshold
#
# Always exits 0. Produces advisory JSON or nothing.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Fast-path: skip if no active session
session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0

readonly LINE_THRESHOLD=50

raw="$(cat)"
tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null || true)"

case "$tool_name" in
  Write|Edit)
    # Audit logging
    printf '%s' "$raw" | jq -c --arg ts "$(iso_timestamp)" '
      {ts: $ts, tool: (.tool_name // ""), file: (.tool_input.file_path // "")}
      | select(.file != "")' >> "${session_dir}/audit.jsonl" 2>/dev/null || true
    ;;
  Bash)
    # Observation mask
    line_count="$(printf '%s' "$raw" | jq -r '.stdout // empty' 2>/dev/null | wc -l | tr -d ' ')"
    line_count="${line_count:-0}"
    if [[ "$line_count" -gt "$LINE_THRESHOLD" ]]; then
      advisory_json "Observation mask: Bash output was ${line_count} lines (threshold: ${LINE_THRESHOLD}). Summarize the key signal (pass/fail, errors, counts) in 5-10 lines rather than processing raw output. Verbose observations fill context without proportional value."
    fi

    # Bash output cache — write stdout (and stderr if present) to a content-
    # addressed file under $session_dir/.bash-cache so that bash-gate.sh can
    # detect identical re-runs and steer the agent to Read+Grep on the cache
    # instead of re-executing the same command for a different filter.
    cache_command="$(printf '%s' "$raw" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
    if [[ -n "$cache_command" ]]; then
      cache_stdout="$(printf '%s' "$raw" | jq -r '.stdout // ""' 2>/dev/null || true)"
      cache_stderr="$(printf '%s' "$raw" | jq -r '.stderr // ""' 2>/dev/null || true)"

      if [[ -n "$cache_stdout" || -n "$cache_stderr" ]]; then
        cache_dir="$(bash_cache_dir 2>/dev/null || true)"

        if [[ -n "$cache_dir" ]]; then
          mkdir -p "$cache_dir" 2>/dev/null || true
          cache_key="$(cmd_hash "$cache_command")"

          if [[ -n "$cache_key" ]]; then
            if [[ -n "$cache_stderr" ]]; then
              printf '%s\n%s' "$cache_stdout" "$cache_stderr" > "${cache_dir}/${cache_key}.txt" 2>/dev/null || true
            else
              printf '%s' "$cache_stdout" > "${cache_dir}/${cache_key}.txt" 2>/dev/null || true
            fi

            printf '%s' "$raw" | jq -c \
              --arg ts "$(iso_timestamp)" \
              --arg hash "$cache_key" \
              --argjson lines "$line_count" \
              '{ts: $ts, hash: $hash, cmd: (.tool_input.command // ""), stdout_lines: $lines}' \
              > "${cache_dir}/${cache_key}.meta.json" 2>/dev/null || true
          fi
        fi
      fi
    fi
    ;;
esac

exit 0
