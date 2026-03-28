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
readonly _CD_AND_PATTERN='^cd[[:space:]]+[^&;]+&&'
readonly _CD_DSEMI_PATTERN='^cd[[:space:]]+[^&;]+;;'
readonly _CD_SEMI_PATTERN='^cd[[:space:]]+[^&;]+;'
readonly _DOLLAR_PAREN_PATTERN='\$\(([^)]*)\)'
readonly _BACKTICK_PATTERN='`([^`]*)`'
readonly _TMP_REDIRECT_PATTERN='>>?[[:space:]]*/tmp/'

# Magic constants extracted as readonly module-level variables
readonly _PROTECTED_BRANCHES="main master production"
readonly _INTERPRETER_BLOCKED_MSG='blocked:Do not run inline interpreter scripts. Use jq for JSON parsing, Grep/Read tools for data extraction, Write tool for file creation. For temporary files, use $RND_DIR instead of /tmp.'

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
  # Remove > <path>/.(claude*|factory)/.rnd/ or .rnd/ token sequences (handles multiple)
  while [[ "$stripped" =~ \>\ *[^[:space:]]*(\.(claude[^/]*|factory)|\.config/opencode)/[^[:space:]]*\.rnd/[^[:space:]]* ]]; do
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
# Prints one of:
#   "blocked:<reason>"  — command should be blocked
#   "echo_safe"         — echo/printf without unsafe redirect
#   "allowed"           — command is safe (no opinion emitted to caller)
#
# NOTE: All conditional branches MUST end with an explicit `printf` or a
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
      printf 'blocked:Use the Edit tool instead of %s. Edit is reviewable, diffable, and handles indentation correctly.' "$cmd"
      return 0
      ;;
    cat)
      printf 'blocked:Use the Read tool instead of %s. Read supports line offsets and limits natively.' "$cmd"
      return 0
      ;;
    head|tail)
      # Allow when used as a pipe filter (no file argument).
      # A file argument is any word that is not a flag (-*) and not a pure
      # number (option-values like the 10 in -n 10 are numbers, not paths).
      local rest="${seg#"$first_word"}"
      rest="${rest#"${rest%%[! ]*}"}"  # ltrim spaces
      local has_file_arg=0
      for word in $rest; do
        if [[ "$word" != -* ]] && ! [[ "$word" =~ ^[0-9]+$ ]]; then
          has_file_arg=1
          break
        fi
      done
      if [[ "$has_file_arg" -eq 1 ]]; then
        printf 'blocked:Use the Read tool instead of %s. Read supports line offsets and limits natively.' "$cmd"
        return 0
      fi
      ;;
    grep|rg)
      printf 'blocked:Use the Grep tool instead of %s. Grep supports regex, file globs, and output modes.' "$cmd"
      return 0
      ;;
    find)
      printf 'blocked:Use the Glob tool instead of find. Glob supports patterns like **/*.ts.'
      return 0
      ;;
    echo|printf)
      local redirect_result
      redirect_result="$(check_echo_redirect "$seg")"
      if [[ "$redirect_result" == "block" ]]; then
        printf 'blocked:Use the Write tool instead of echo/printf with file redirects. Write is reviewable and creates proper diffs.'
        return 0
      else
        # Safe echo/printf (no redirect, or redirect to .rnd/ or /dev/)
        printf 'echo_safe'
        return 0
      fi
      ;;
    python|python3)
      # Extract the second word (first argument to the interpreter)
      local rest="${seg#"$first_word"}"
      rest="${rest#"${rest%%[! ]*}"}"  # ltrim spaces
      local second_word="${rest%% *}"
      if [[ -z "$second_word" ]]; then
        # Bare interpreter: e.g. "python3" alone — pipe target like echo | python3
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      elif [[ "$second_word" == "-m" ]]; then
        printf 'allowed'
        return 0
      elif [[ "$second_word" == *.py ]] || [[ "$second_word" == */* ]]; then
        printf 'allowed'
        return 0
      elif [[ "$second_word" == "-c" ]] || [[ "$seg" == *" -c "* ]] || [[ "$seg" == *" -c'"* ]]; then
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      else
        printf 'allowed'
        return 0
      fi
      ;;
    node)
      local rest="${seg#"$first_word"}"
      rest="${rest#"${rest%%[! ]*}"}"
      local second_word="${rest%% *}"
      if [[ -z "$second_word" ]]; then
        # Bare node — pipe target
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      elif [[ "$second_word" == "-e" ]] || [[ "$seg" == *" -e "* ]] || [[ "$seg" == *" -e'"* ]]; then
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      else
        printf 'allowed'
        return 0
      fi
      ;;
    bun)
      local rest="${seg#"$first_word"}"
      rest="${rest#"${rest%%[! ]*}"}"
      local second_word="${rest%% *}"
      if [[ -z "$second_word" ]]; then
        # Bare bun — pipe target
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      elif [[ "$second_word" == "eval" ]]; then
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      elif [[ "$second_word" == "-e" ]] || [[ "$seg" == *" -e "* ]] || [[ "$seg" == *" -e'"* ]]; then
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      else
        printf 'allowed'
        return 0
      fi
      ;;
    perl|ruby)
      if [[ "$seg" == *" -e "* ]] || [[ "$seg" == *" -e'"* ]] || [[ "${seg#"$first_word" }" == "-e"* ]]; then
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      else
        printf 'allowed'
        return 0
      fi
      ;;
  esac
  # Default: no opinion on this command
  printf 'allowed'
}

# ---------------------------------------------------------------------------
# split_and_check: splits command into segments and checks each.
# Prints structured result on stdout:
#   "blocked:<reason>"  — first violation found
#   "echo_safe"         — at least one safe echo/printf, no violations
#   "allowed"           — no violations
# ---------------------------------------------------------------------------
split_and_check() {
  local command="$1"
  local _has_echo=0
  local _result

  # Step 1: extract $(...) contents and check them as additional segments
  local temp="$command"
  while [[ "$temp" =~ $_DOLLAR_PAREN_PATTERN ]]; do
    local inner="${BASH_REMATCH[1]}"
    _result="$(check_segment "${inner# }")" || true
    if [[ "$_result" == blocked:* ]]; then
      printf '%s' "$_result"
      return 0
    fi
    temp="${temp/${BASH_REMATCH[0]}/}"
  done

  # Step 2: extract backtick contents
  temp="$command"
  while [[ "$temp" =~ $_BACKTICK_PATTERN ]]; do
    local inner="${BASH_REMATCH[1]}"
    _result="$(check_segment "${inner# }")" || true
    if [[ "$_result" == blocked:* ]]; then
      printf '%s' "$_result"
      return 0
    fi
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

  # Use herestring so the while loop runs in the current shell (not a subshell),
  # allowing _has_echo to be visible after the loop. <<< adds a trailing newline
  # so read never sees a no-newline EOF that would silently drop the last segment.
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
    _result="$(check_segment "$seg")" || true
    if [[ "$_result" == blocked:* ]]; then
      printf '%s' "$_result"
      return 0
    fi
    if [[ "$_result" == "echo_safe" ]]; then
      _has_echo=1
    fi
  done <<< "$split_cmd"

  if [[ "$_has_echo" -eq 1 ]]; then
    printf 'echo_safe'
  else
    printf 'allowed'
  fi
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

# Block: git add .rnd/ or .rnd/ (must be followed by / or space or end)
if [[ "$command" =~ git[[:space:]]+add.*\.rnd(/|[[:space:]]|$) ]]; then
  block_msg "BLOCKED: Plugin artifact directories (.rnd/, .rnd/) must never be committed."
fi

# Block: git push to protected branches (listed in _PROTECTED_BRANCHES)
_branch_pattern="${_PROTECTED_BRANCHES// /|}"
if [[ "$command" =~ git[[:space:]]+push[[:space:]].*[[:space:]]($_branch_pattern)([[:space:]]|$) ]]; then
  block_msg "BLOCKED: Direct push to main/master/production. Use a feature branch and PR instead."
fi
unset _branch_pattern

# ---------------------------------------------------------------------------
# /tmp redirect guard — checked on the full command string (before splitting)
# Catches patterns like: npm test > /tmp/log.txt  or  cmd >> /tmp/append.txt
# For simple echo/printf commands (no shell operators), check_echo_redirect
# already catches the redirect with a "Write tool" message, so we skip the
# /tmp guard for those. For compound commands (containing &&, ||, ;, |) we
# always check, even if the first segment is echo/printf, because the /tmp
# redirect may be in a later segment that check_echo_redirect never sees.
# ---------------------------------------------------------------------------
_is_compound=0
if [[ "$command" == *"&&"* || "$command" == *"||"* || "$command" == *";"* || "$command" == *"|"* ]]; then
  _is_compound=1
fi
_cmd_first_word="${command%% *}"
_cmd_name="${_cmd_first_word##*/}"
_skip_tmp_guard=0
if [[ "$_is_compound" -eq 0 && ( "$_cmd_name" == "echo" || "$_cmd_name" == "printf" ) ]]; then
  _skip_tmp_guard=1
fi
if [[ "$_skip_tmp_guard" -eq 0 ]] && [[ "$command" =~ $_TMP_REDIRECT_PATTERN ]]; then
  block_msg "Do not write to /tmp. Use \$RND_DIR for temporary files — it is auto-allowed and persists across the pipeline session."
fi

# ---------------------------------------------------------------------------
# Tool discipline — split into segments, check each
# (runs before .rnd/ auto-allow so cat/sed on .rnd/ paths is still blocked)
# ---------------------------------------------------------------------------

_discipline_result="$(split_and_check "$command")" || true

if [[ "$_discipline_result" == blocked:* ]]; then
  block_msg "${_discipline_result#blocked:}"
fi

# ---------------------------------------------------------------------------
# echo/printf without unsafe redirect — auto-allow
# ---------------------------------------------------------------------------

if [[ "$_discipline_result" == "echo_safe" ]]; then
  allow_json
  exit 0
fi

# ---------------------------------------------------------------------------
# Auto-allow plugin artifact paths (.rnd/, .rnd/) and dir helper commands
# (placed after tool discipline so sed/cat on these paths is still blocked)
# ---------------------------------------------------------------------------

if [[ "$command" =~ (\.(claude[^/]*|factory)|\.config/opencode)/.*\.rnd/ ]] || [[ "$command" == *"rnd-dir.sh"* ]] || [[ "$command" == *"rnd-dir.sh"* ]]; then
  allow_json
  exit 0
fi

# Auto-allow plugin lib/ scripts (bump.sh, validate.sh, etc.)
plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$plugin_root" ]] && [[ "$command" == *"${plugin_root}/lib/"* ]]; then
  allow_json
  exit 0
fi

# No opinion — let Claude Code default permission system handle it
exit 0
