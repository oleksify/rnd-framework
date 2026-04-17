#!/usr/bin/env bash
# hooks/bash-gate.sh — Unified PreToolUse hook for Bash/Execute.
#
# Merged from db-guard.sh + prefer-tools.sh into a single dispatcher.
# Fast-path: exits immediately when no active RND session.
#
# Responsibilities:
#   1. Database guard — blocks destructive DB operations (Ecto, Postgres, MySQL, SQLite)
#   2. Git guards — blocks git add .rnd/ and git push to protected branches
#   3. Shell loop guard — blocks for/while/until loops (they hang in the Bash tool)
#   4. /tmp redirect guard — steers writes to $RND_DIR
#   5. Tool discipline — blocks sed/awk/cat/grep/find/echo-redirects/inline interpreters
#   6. Auto-allow — .rnd/ paths, echo/printf without redirect, plugin lib scripts
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
# CD patterns: [^&;]+ assumes paths don't contain literal & or ; (they should be quoted).
readonly _CD_AND_PATTERN='^cd[[:space:]]+[^&;]+&&'
readonly _CD_DSEMI_PATTERN='^cd[[:space:]]+[^&;]+;;'
readonly _CD_SEMI_PATTERN='^cd[[:space:]]+[^&;]+;'
readonly _DOLLAR_PAREN_PATTERN='\$\(([^)]*)\)'
readonly _BACKTICK_PATTERN='`([^`]*)`'
readonly _TMP_REDIRECT_PATTERN='>>?[[:space:]]*/tmp/'
readonly _PROTECTED_BRANCHES="main master production"
readonly _INTERPRETER_BLOCKED_MSG='blocked:Do not run inline interpreter scripts. Use jq for JSON parsing, Grep/Read tools for data extraction, Write tool for file creation. For temporary files, use $RND_DIR instead of /tmp.'

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
  while [[ "$stripped" =~ \>\ *[^[:space:]]*\.claude[^/]*/[^[:space:]]*\.rnd/[^[:space:]]* ]]; do
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

# Strips leading environment variable assignments (e.g., FOO=bar BAZ=quux)
# from a command segment. Env-var prefixes match [A-Za-z_][A-Za-z_0-9]*=<value>.
# The value may be quoted or unquoted.
#
# Note: This is orthogonal to upstream Accept Edits mode (v2.1.97+), which
# auto-approves filesystem commands prefixed with safe env vars. Our stripping
# enforces tool discipline (which tool to use — Edit vs sed, Read vs cat),
# while upstream decides whether to prompt for permission on the tool call.
strip_env_prefix() {
  local seg="$1"
  local _ENV_VAR_PATTERN='^[A-Za-z_][A-Za-z_0-9]*='
  while [[ "$seg" =~ $_ENV_VAR_PATTERN ]]; do
    local first_word="${seg%% *}"
    # If the entire segment is a single env assignment, no command follows
    if [[ "$first_word" == "$seg" ]]; then
      printf '%s' "$seg"
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
      local rest
      rest="$(_args_after_cmd "$seg" "$first_word")"
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
      local rest
      rest="$(_args_after_cmd "$seg" "$first_word")"
      local non_flag_count=0
      local has_recursive=0
      for word in $rest; do
        if [[ "$word" == -* ]]; then
          case "$word" in -r|-R|--recursive) has_recursive=1 ;; esac
          continue
        fi
        non_flag_count=$((non_flag_count + 1))
      done
      # Block if: recursive flag (searches cwd) or 2+ non-flag args (pattern + file).
      # Allow if: only pattern, no file — stdin filter (e.g., git diff | grep pattern).
      if [[ "$has_recursive" -eq 1 ]] || [[ "$non_flag_count" -ge 2 ]]; then
        printf 'blocked:Use the Grep tool instead of %s. Grep supports regex, file globs, and output modes.' "$cmd"
        return 0
      fi
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

raw="$(cat)"
command="$(printf '%s' "$raw" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
_agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

if [[ -z "$command" ]]; then exit 0; fi

cmd_lower="$(_lower "$command")"

# ---------------------------------------------------------------------------
# 0. Information barrier — self-assessment files
# ---------------------------------------------------------------------------
# Blocks any Bash command referencing self-assessment content when the agent
# is a verifier or has no declared agent_type. Mirrors the barrier in
# read-gate.sh so that commands like diff, jq, less, strings, etc. cannot
# be used to read self-assessment files around the Read tool's guard.

if is_barrier_violation "$command" "$_agent_type"; then
  block_msg "INFORMATION BARRIER: self-assessment files are write-only records for the orchestrator. Direct reading is blocked to maintain information barriers between Builder and Verifier."
fi

# ---------------------------------------------------------------------------
# 1. Database guard (from db-guard.sh)
# ---------------------------------------------------------------------------

# Ecto destructive commands without MIX_ENV=test
if [[ "$cmd_lower" == *"mix ecto.reset"* ]] || [[ "$cmd_lower" == *"mix ecto.drop"* ]]; then
  if [[ "$cmd_lower" != *"mix_env=test"* ]]; then
    block_msg "BLOCKED: \`mix ecto.reset\` destroys the dev database. Only MIX_ENV=test is allowed for destructive Ecto commands."
  fi
fi

# Direct database file deletion
if [[ "$cmd_lower" =~ rm[[:space:]] ]]; then
  if [[ "$cmd_lower" =~ \.(db|sqlite|sqlite3)([[:space:]]|$) ]]; then
    block_msg "BLOCKED: Refusing to delete database file. Database files (.db, .sqlite, .sqlite3) are protected."
  fi
fi

# PostgreSQL destructive commands
if [[ "$cmd_lower" =~ (^|[[:space:];&|])dropdb([[:space:]]|$) ]]; then
  block_msg "BLOCKED: Destructive PostgreSQL operation. Use MIX_ENV=test for test databases only."
fi
if [[ "$cmd_lower" =~ psql.*-c.*drop[[:space:]]+database ]]; then
  block_msg "BLOCKED: Destructive PostgreSQL operation. Use MIX_ENV=test for test databases only."
fi
if [[ "$cmd_lower" =~ pg_restore.*--clean ]]; then
  block_msg "BLOCKED: Destructive PostgreSQL operation. Use MIX_ENV=test for test databases only."
fi

# MySQL destructive commands
if [[ "$cmd_lower" =~ mysqladmin.*drop ]]; then
  block_msg "BLOCKED: Destructive MySQL operation. Use test databases only."
fi
if [[ "$cmd_lower" =~ mysql[[:space:]].*-e.*drop[[:space:]]+database ]]; then
  block_msg "BLOCKED: Destructive MySQL operation. Use test databases only."
fi

# SQLite destructive SQL via CLI
if [[ "$cmd_lower" =~ sqlite3[[:space:]] ]]; then
  if [[ "$cmd_lower" =~ (delete[[:space:]]+from|drop[[:space:]]+table|drop[[:space:]]+index) ]]; then
    block_msg "BLOCKED: Destructive SQLite SQL. Use application code for data modifications."
  fi
fi

# Advisory warnings for dev database operations
if [[ "$cmd_lower" == *"mix_env=dev"* ]]; then
  if [[ "$cmd_lower" == *"mix ecto.create"* ]]; then
    advisory_json "Advisory: Running ecto.create on dev database. Prefer MIX_ENV=test for automated environments."
    exit 0
  fi
  if [[ "$cmd_lower" == *"mix ecto.migrate"* ]]; then
    advisory_json "Advisory: Running ecto.migrate on dev database. Migrations can alter schema unexpectedly in automated environments."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# 2. Git guards (from prefer-tools.sh)
# ---------------------------------------------------------------------------

if [[ "$command" =~ git[[:space:]]+add.*\.rnd(/|[[:space:]]|$) ]]; then
  block_msg "BLOCKED: Plugin artifact directories (.rnd/) must never be committed."
fi

_branch_pattern="${_PROTECTED_BRANCHES// /|}"
if [[ "$command" =~ git[[:space:]]+push[[:space:]].*[[:space:]]($_branch_pattern)([[:space:]]|$) ]]; then
  advisory_json "WARNING: You are about to push directly to a protected branch (main/master/production). Ask the user for explicit confirmation before proceeding."
  exit 0
fi
unset _branch_pattern

# ---------------------------------------------------------------------------
# 3. Shell loop guard
# ---------------------------------------------------------------------------
# Detects for/while/until loops which frequently hang in the Bash tool.
# Requires both the loop keyword AND the `do` keyword to avoid false positives
# on commands that merely contain the word "for" (e.g., `echo "search for files"`).

if [[ "$cmd_lower" =~ (^|[[:space:];\&\|])for[[:space:]] ]] && [[ "$cmd_lower" =~ [[:space:]\;]do([[:space:]\;]|$) ]]; then
  block_msg "Avoid shell for-loops — they frequently hang in the Bash tool. Use the Glob tool to list files and the Grep tool to search content. For cross-referencing, use Grep with alternation patterns or multiple parallel tool calls."
fi

if [[ "$cmd_lower" =~ (^|[[:space:];\&\|])(while|until)[[:space:]] ]] && [[ "$cmd_lower" =~ [[:space:]\;]do([[:space:]\;]|$) ]]; then
  block_msg "Avoid shell while/until loops — they can hang in the Bash tool. Use dedicated tools (Glob, Grep, Read) for file operations."
fi

# ---------------------------------------------------------------------------
# 4. /tmp redirect guard
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
# 5. Tool discipline
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
# 6. Auto-allow plugin artifact paths and lib scripts
# ---------------------------------------------------------------------------

if [[ "$command" =~ \.claude[^/]*/.*\.rnd/ ]] || [[ "$command" == *"rnd-dir.sh"* ]]; then
  allow_json
  exit 0
fi

plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$plugin_root" ]] && [[ "$command" == *"${plugin_root}/lib/"* ]]; then
  allow_json
  exit 0
fi

exit 0
