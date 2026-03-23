#!/usr/bin/env bash
# hooks/prefer-tools.sh — PreToolUse hook for Bash: enforces tool discipline.
#
# Blocks sed/awk (→ Edit tool), cat/head/tail (→ Read tool),
# grep/rg (→ Grep tool), find (→ Glob tool), and echo/printf
# with file redirects (→ Write tool). Also guards git add .rnd/ and
# git push to protected branches.
#
# This is best-effort advisory enforcement, not a security sandbox.
# Shell parsing is simplified: it does not handle quoted strings,
# heredocs, or deeply nested substitutions.
#
# Exit codes:
#   0 + hookSpecificOutput JSON  — auto-allow
#   0 + no stdout               — no opinion
#   2 + stderr message          — blocked
#
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# Regex patterns stored in variables to avoid bash special-char issues in
# [[ =~ ]] when the pattern itself contains && or special sequences.
# ---------------------------------------------------------------------------
_CD_AND_PATTERN='^cd[[:space:]]+[^&;]+&&'
_CD_DSEMI_PATTERN='^cd[[:space:]]+[^&;]+;;'
_CD_SEMI_PATTERN='^cd[[:space:]]+[^&;]+;'
_DOLLAR_PAREN_PATTERN='\$\(([^)]*)\)'
_BACKTICK_PATTERN='`([^`]*)`'

# ---------------------------------------------------------------------------
# Global state (set by check_segment, read by main)
# ---------------------------------------------------------------------------
SEGMENT_BLOCKED=0
BLOCK_REASON=""
HAS_ECHO=0

# ---------------------------------------------------------------------------
# check_echo_redirect: prints "block" or "allow"
# Strips safe redirects (> /dev/... and > .../.rnd/...) then checks for
# remaining > characters.
# ---------------------------------------------------------------------------
check_echo_redirect() {
  local seg="$1"
  local stripped="$seg"
  # Remove > /dev/<token> sequences (handles multiple)
  while [[ "$stripped" =~ \>\ */dev/[^[:space:]]* ]]; do
    stripped="${stripped//${BASH_REMATCH[0]}/}"
  done
  # Remove > <path>/.rnd/<token> sequences (handles multiple)
  while [[ "$stripped" =~ \>\ *[^[:space:]]*\.rnd/[^[:space:]]* ]]; do
    stripped="${stripped//${BASH_REMATCH[0]}/}"
  done
  if [[ "$stripped" == *">"* ]]; then
    printf 'block'
  else
    printf 'allow'
  fi
}

# ---------------------------------------------------------------------------
# strip_cd_prefix: strips leading "cd <path> &&", "cd <path>;", "cd <path>;;"
# Applied repeatedly until stable (handles chained cds). Prints result.
# ---------------------------------------------------------------------------
strip_cd_prefix() {
  local seg="$1"
  local prev
  while true; do
    prev="$seg"
    # Strip "cd <path> && " prefix (double-ampersand AND)
    if [[ "$seg" =~ $_CD_AND_PATTERN ]]; then
      seg="${seg#*&&}"
      seg="${seg#"${seg%%[! ]*}"}"  # ltrim spaces
    # Strip "cd <path> ;; " prefix (double semicolon — must come before single)
    elif [[ "$seg" =~ $_CD_DSEMI_PATTERN ]]; then
      seg="${seg#*;;}"
      seg="${seg#"${seg%%[! ]*}"}"
    # Strip "cd <path> ; " prefix (single semicolon)
    elif [[ "$seg" =~ $_CD_SEMI_PATTERN ]]; then
      seg="${seg#*;}"
      seg="${seg#"${seg%%[! ]*}"}"
    else
      break
    fi
    [[ "$seg" == "$prev" ]] && break
  done
  printf '%s' "$seg"
}

# ---------------------------------------------------------------------------
# check_segment: checks one command segment.
# Sets SEGMENT_BLOCKED=1 + BLOCK_REASON on violation.
# Sets HAS_ECHO=1 for safe echo/printf.
#
# NOTE: All conditional branches MUST end with an explicit `true` or a
# command that always exits 0, because this function is called from inside
# a while loop and with set -e active. If the LAST command executed before
# return exits non-zero, set -e fires on the caller.
# ---------------------------------------------------------------------------
check_segment() {
  local seg
  seg="$(strip_cd_prefix "$1")"

  # Strip leading path prefix from command name (e.g. /usr/bin/grep → grep)
  local first_word="${seg%% *}"
  local cmd="${first_word##*/}"

  case "$cmd" in
    sed|awk)
      SEGMENT_BLOCKED=1
      BLOCK_REASON="Use the Edit tool instead of ${cmd}. Edit is reviewable, diffable, and handles indentation correctly."
      ;;
    cat|head|tail)
      SEGMENT_BLOCKED=1
      BLOCK_REASON="Use the Read tool instead of ${cmd}. Read supports line offsets and limits natively."
      ;;
    grep|rg)
      SEGMENT_BLOCKED=1
      BLOCK_REASON="Use the Grep tool instead of ${cmd}. Grep supports regex, file globs, and output modes."
      ;;
    find)
      SEGMENT_BLOCKED=1
      BLOCK_REASON="Use the Glob tool instead of find. Glob supports patterns like **/*.ts."
      ;;
    echo|printf)
      local redirect_result
      redirect_result="$(check_echo_redirect "$seg")"
      if [[ "$redirect_result" == "block" ]]; then
        SEGMENT_BLOCKED=1
        BLOCK_REASON="Use the Write tool instead of echo/printf with file redirects. Write is reviewable and creates proper diffs."
      else
        # Safe echo/printf (no redirect, or redirect to .rnd/ or /dev/)
        HAS_ECHO=1
      fi
      ;;
  esac
  # Explicit true to ensure the function always exits 0 (important: this
  # function is called as the last command in a while loop body, so its
  # exit code becomes the while block's exit code — must be 0 or set -e fires)
  true
}

# ---------------------------------------------------------------------------
# split_and_check: splits command into segments and checks each.
# Returns early (non-locally, via setting SEGMENT_BLOCKED) on first violation.
# ---------------------------------------------------------------------------
split_and_check() {
  local command="$1"

  # Step 1: extract $(...) contents and check them as additional segments
  local temp="$command"
  while [[ "$temp" =~ $_DOLLAR_PAREN_PATTERN ]]; do
    local inner="${BASH_REMATCH[1]}"
    check_segment "${inner# }"
    if [[ "$SEGMENT_BLOCKED" -eq 1 ]]; then return; fi
    temp="${temp/${BASH_REMATCH[0]}/}"
  done

  # Step 2: extract backtick contents
  temp="$command"
  while [[ "$temp" =~ $_BACKTICK_PATTERN ]]; do
    local inner="${BASH_REMATCH[1]}"
    check_segment "${inner# }"
    if [[ "$SEGMENT_BLOCKED" -eq 1 ]]; then return; fi
    temp="${temp/${BASH_REMATCH[0]}/}"
  done

  # Step 3: split on shell operators: &&, ||, ;, |
  # Replace operators with newlines, then read line by line.
  # Order: replace && before |, replace || before |, so | is replaced last
  # for any remaining lone pipe characters.
  local split_cmd
  split_cmd="${command//&&/$'\n'}"
  split_cmd="${split_cmd//||/$'\n'}"
  split_cmd="${split_cmd//;/$'\n'}"
  split_cmd="${split_cmd//|/$'\n'}"

  while IFS= read -r seg; do
    # Strip leading/trailing whitespace
    seg="${seg#"${seg%%[! ]*}"}"
    seg="${seg%"${seg##*[! ]}"}"
    # Strip leading ( for subshells
    seg="${seg#\(}"
    seg="${seg#"${seg%%[! ]*}"}"
    # Strip trailing )
    seg="${seg%\)}"
    if [[ -z "$seg" ]]; then continue; fi
    check_segment "$seg"
    if [[ "$SEGMENT_BLOCKED" -eq 1 ]]; then return; fi
  done <<< "$split_cmd"
  true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

raw="$(cat)"
command="$(printf '%s' "$raw" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"

# Empty or malformed input — no opinion
if [[ -z "$command" ]]; then exit 0; fi

# ---------------------------------------------------------------------------
# Git guards — checked on the full command string (before splitting)
# ---------------------------------------------------------------------------

# Block: git add .rnd/ (must be followed by / or space or end, not .rnd.something)
if [[ "$command" =~ git[[:space:]]+add.*\.rnd(/|[[:space:]]|$) ]]; then
  block_msg "BLOCKED: .rnd/ is a pipeline artifact directory and must never be committed."
fi

# Block: git push to main/master/production
if [[ "$command" =~ git[[:space:]]+push[[:space:]].*[[:space:]](main|master|production)([[:space:]]|$) ]]; then
  block_msg "BLOCKED: Direct push to main/master/production. Use a feature branch and PR instead."
fi

# ---------------------------------------------------------------------------
# Tool discipline — split into segments, check each
# (runs before .rnd/ auto-allow so cat/sed on .rnd/ paths is still blocked)
# ---------------------------------------------------------------------------

split_and_check "$command"

if [[ "$SEGMENT_BLOCKED" -eq 1 ]]; then
  block_msg "$BLOCK_REASON"
fi

# ---------------------------------------------------------------------------
# echo/printf without unsafe redirect — auto-allow
# ---------------------------------------------------------------------------

if [[ "$HAS_ECHO" -eq 1 ]]; then
  allow_json
  exit 0
fi

# ---------------------------------------------------------------------------
# Auto-allow .rnd/ paths and rnd-dir.sh commands
# (placed after tool discipline so sed/cat on .rnd/ is still blocked)
# ---------------------------------------------------------------------------

if [[ "$command" == *".rnd/"* ]] || [[ "$command" == *"rnd-dir.sh"* ]]; then
  allow_json
  exit 0
fi

# Auto-allow plugin lib/ scripts (bump.sh, extract-patterns.ts, etc.)
plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$plugin_root" ]] && [[ "$command" == *"${plugin_root}/lib/"* ]]; then
  allow_json
  exit 0
fi

# No opinion — let Claude Code default permission system handle it
exit 0
