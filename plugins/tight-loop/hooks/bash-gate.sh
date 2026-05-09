#!/usr/bin/env bash
# hooks/bash-gate.sh — Unified PreToolUse hook for Bash/Execute.
#
# Responsibilities:
#   1. Git guards — blocks git add .tight-loop/ and git push to protected branches
#   2. Shell loop guard — blocks for/while/until loops (they hang in the Bash tool)
#   3. /tmp redirect guard — steers writes to tight-loop artifact dir
#   4. Tool discipline — blocks sed/awk/echo-redirects/inline interpreters
#   5. Auto-allow — .tight-loop/ paths, echo/printf without redirect
#
# Exit codes:
#   0 + hookSpecificOutput JSON  — auto-allow
#   0 + advisory JSON           — warning (does not block)
#   0 + no stdout               — no opinion
#   2 + stderr message          — blocked
#
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# Regex patterns
# ---------------------------------------------------------------------------

readonly _CD_AND_PATTERN='^cd[[:space:]]+[^&;]+&&'
readonly _CD_DSEMI_PATTERN='^cd[[:space:]]+[^&;]+;;'
readonly _CD_SEMI_PATTERN='^cd[[:space:]]+[^&;]+;'
readonly _DOLLAR_PAREN_PATTERN='\$\(([^)]*)\)'
readonly _BACKTICK_PATTERN='`([^`]*)`'
readonly _TMP_REDIRECT_PATTERN='>>?[[:space:]]*/tmp/'
readonly _PROTECTED_BRANCHES="main master production"
readonly _INTERPRETER_BLOCKED_MSG='blocked:Do not run inline interpreter scripts. Use jq for JSON parsing, Grep/Read tools for data extraction, Write tool for file creation. For temporary files, use the tight-loop artifact directory instead of /tmp.'

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Extracts args after the command name and left-trims whitespace.
_args_after_cmd() {
  local seg="$1" first_word="$2"
  local rest="${seg#"$first_word"}"
  printf '%s' "${rest#"${rest%%[! ]*}"}"
}

# Checks if a segment invokes an interpreter with an inline eval flag (-c or -e).
# Returns: "blocked:..." if inline eval, "allowed" if file execution, "$_INTERPRETER_BLOCKED_MSG" if bare interpreter.
_check_interpreter() {
  local seg="$1" first_word="$2" flag="$3"
  local rest
  rest="$(_args_after_cmd "$seg" "$first_word")"
  local second_word="${rest%% *}"

  if [[ -z "$second_word" ]]; then
    printf '%s' "$_INTERPRETER_BLOCKED_MSG"; return 0
  fi

  if [[ "$second_word" == "$flag" ]] || [[ "$seg" == *" ${flag} "* ]] || [[ "$seg" == *" ${flag}'"* ]]; then
    printf '%s' "$_INTERPRETER_BLOCKED_MSG"; return 0
  fi

  printf 'allowed'
}

check_echo_redirect() {
  local seg="$1"
  local stripped="$seg"

  while [[ "$stripped" =~ \>\ */dev/[^[:space:]]* ]]; do
    stripped="${stripped//${BASH_REMATCH[0]}/}"
  done

  while [[ "$stripped" =~ \>\ *[^[:space:]]*\.claude[^/]*/[^[:space:]]*\.tight-loop/[^[:space:]]* ]]; do
    stripped="${stripped//${BASH_REMATCH[0]}/}"
  done

  while [[ "$stripped" =~ 2\>\ *\&[[:digit:]] ]]; do
    stripped="${stripped//${BASH_REMATCH[0]}/}"
  done

  while [[ "$stripped" =~ 2\>\ */dev/[^[:space:]]* ]]; do
    stripped="${stripped//${BASH_REMATCH[0]}/}"
  done

  if [[ "$stripped" == *">"* ]]; then
    printf 'block'
  else
    printf 'allow'
  fi
}

strip_cd_prefix() {
  local seg="$1"
  local prev

  while true; do
    prev="$seg"

    if [[ "$seg" =~ $_CD_AND_PATTERN ]]; then
      seg="${seg#*&&}"
      seg="${seg#"${seg%%[! ]*}"}"
    elif [[ "$seg" =~ $_CD_DSEMI_PATTERN ]]; then
      seg="${seg#*;;}"
      seg="${seg#"${seg%%[! ]*}"}"
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

strip_env_prefix() {
  local seg="$1"
  local _ENV_VAR_PATTERN='^[A-Za-z_][A-Za-z_0-9]*='

  while [[ "$seg" =~ $_ENV_VAR_PATTERN ]]; do
    local first_word="${seg%% *}"

    if [[ "$first_word" == "$seg" ]]; then
      printf '%s' "$seg"
      return 0
    fi

    local _value="${first_word#*=}"
    if [[ "$_value" == '"'* && "$_value" != *'"' ]] || \
       [[ "$_value" == "'"* && "$_value" != *"'" ]]; then
      printf 'blocked:BLOCKED: Env-var prefix with a quoted value containing spaces (e.g. FOO="abc def") cannot be safely stripped. Remove the env-var assignment and use the appropriate tool directly.'
      return 0
    fi

    seg="${seg#"$first_word"}"
    seg="${seg#"${seg%%[! ]*}"}"
  done

  printf '%s' "$seg"
}

check_segment() {
  local seg
  seg="$(strip_cd_prefix "$1")"
  seg="$(strip_env_prefix "$seg")"

  if [[ "$seg" == blocked:* ]]; then
    printf '%s' "$seg"
    return 0
  fi

  local first_word="${seg%% *}"
  local cmd="${first_word##*/}"

  case "$cmd" in
    git)
      if [[ "$seg" =~ ^git[[:space:]]+add[[:space:]]+.*\.tight-loop(/|[[:space:]]|$) ]]; then
        printf 'blocked:BLOCKED: Plugin artifact directories (.tight-loop/) must never be committed.'
        return 0
      fi
      ;;
    sed|awk)
      printf 'blocked:Use the Edit tool instead of %s. Edit is reviewable, diffable, and handles indentation correctly.' "$cmd"
      return 0
      ;;
    echo|printf)
      local redirect_result
      redirect_result="$(check_echo_redirect "$seg")"

      if [[ "$redirect_result" == "block" ]]; then
        printf 'blocked:Use the Write tool instead of echo/printf with file redirects. Write is reviewable and creates proper diffs.'
        return 0
      else
        printf 'echo_safe'
        return 0
      fi
      ;;
    python|python3)
      local rest
      rest="$(_args_after_cmd "$seg" "$first_word")"
      local second_word="${rest%% *}"

      if [[ -z "$second_word" ]]; then
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      elif [[ "$second_word" == "-m" ]] || [[ "$second_word" == *.py ]] || [[ "$second_word" == */* ]]; then
        printf 'allowed'
        return 0
      fi

      _check_interpreter "$seg" "$first_word" "-c"
      return 0
      ;;
    node)
      _check_interpreter "$seg" "$first_word" "-e"
      return 0
      ;;
    bun)
      local rest
      rest="$(_args_after_cmd "$seg" "$first_word")"
      local second_word="${rest%% *}"

      if [[ -z "$second_word" ]]; then
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      elif [[ "$second_word" == "eval" ]]; then
        printf '%s' "$_INTERPRETER_BLOCKED_MSG"
        return 0
      fi

      _check_interpreter "$seg" "$first_word" "-e"
      return 0
      ;;
    perl|ruby)
      _check_interpreter "$seg" "$first_word" "-e"
      return 0
      ;;
  esac

  printf 'allowed'
}

split_and_check() {
  local command="$1"
  local _has_echo=0
  local _result

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

  local split_cmd
  split_cmd="${command//&&/$'\n'}"
  split_cmd="${split_cmd//||/$'\n'}"
  split_cmd="${split_cmd//;/$'\n'}"
  split_cmd="${split_cmd//|/$'\n'}"

  while IFS= read -r seg; do
    seg="${seg#"${seg%%[! ]*}"}"
    seg="${seg%"${seg##*[! ]}"}"
    seg="${seg#\(}"
    seg="${seg#"${seg%%[! ]*}"}"
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

parse_input
command="$(printf '%s' "$TOOL_INPUT" | jq -r '.command // ""')"

if [[ -z "$command" ]]; then exit 0; fi

cmd_lower="$(_lower "$command")"

# ---------------------------------------------------------------------------
# 1. Git guards
# ---------------------------------------------------------------------------

_branch_pattern="${_PROTECTED_BRANCHES// /|}"
if [[ "$command" =~ git[[:space:]]+push[[:space:]].*[[:space:]:]($_branch_pattern)([[:space:]]|$) ]]; then
  advisory_json "WARNING: You are about to push directly to a protected branch (main/master/production). Ask the user for explicit confirmation before proceeding."
  exit 0
fi
unset _branch_pattern

# ---------------------------------------------------------------------------
# 2. Shell loop guard
# ---------------------------------------------------------------------------

if [[ "$cmd_lower" =~ (^|[[:space:];\&\|])for[[:space:]] ]] && [[ "$cmd_lower" =~ (;|[[:space:]])do((;|[[:space:]])|$) ]]; then
  block_msg "Avoid shell for-loops — they frequently hang in the Bash tool. Use the Glob tool to list files and the Grep tool to search content. For cross-referencing, use Grep with alternation patterns or multiple parallel tool calls."
fi

if [[ "$cmd_lower" =~ (^|[[:space:];\&\|])(while|until)[[:space:]] ]] && [[ "$cmd_lower" =~ (;|[[:space:]])do((;|[[:space:]])|$) ]]; then
  block_msg "Avoid shell while/until loops — they can hang in the Bash tool. Use dedicated tools (Glob, Grep, Read) for file operations."
fi

# ---------------------------------------------------------------------------
# 3. /tmp redirect guard
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
  block_msg "Do not write to /tmp. Use the tight-loop artifact directory for temporary files — it is auto-allowed and persists across the session."
fi

# ---------------------------------------------------------------------------
# 4. Tool discipline
# ---------------------------------------------------------------------------

_discipline_result="$(split_and_check "$command")" || true

if [[ "$_discipline_result" == blocked:* ]]; then
  block_msg "${_discipline_result#blocked:}"
fi

# echo/printf without unsafe redirect — auto-allow
if [[ "$_discipline_result" == "echo_safe" ]]; then
  allow_json
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Auto-allow plugin artifact paths
# ---------------------------------------------------------------------------

if [[ "$command" =~ \.claude[^/]*/.*\.tight-loop/ ]] || [[ "$command" =~ (^|/)tight-dir\.sh($|[[:space:]\"\']) ]]; then
  allow_json
  exit 0
fi

plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$plugin_root" ]] && [[ "$command" == *"${plugin_root}/lib/"* ]]; then
  allow_json
  exit 0
fi

exit 0
