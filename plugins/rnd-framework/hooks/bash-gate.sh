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
#   5. Tool discipline — blocks sed/awk/echo-redirects/inline interpreters
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

# Strips leading environment variable assignments (e.g., FOO=bar BAZ=quux)
# from a command segment. Env-var prefixes match [A-Za-z_][A-Za-z_0-9]*=<value>.
# The value may be quoted or unquoted.
#
# Note: This is orthogonal to upstream Accept Edits mode (v2.1.97+), which
# auto-approves filesystem commands prefixed with safe env vars. Our stripping
# enforces tool discipline (which tool to use — Edit vs sed, Read vs cat),
# while upstream decides whether to prompt for permission on the tool call.
#
# Quoted values with internal spaces (e.g. FOO="abc def") are detected and
# blocked immediately: strip_env_prefix identifies an unmatched leading quote in
# the value portion of first_word and emits a blocked: message rather than
# attempting to strip an incomplete prefix.
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
    # Detect unmatched quote in the value portion of the env prefix.
    # A quoted value containing spaces (e.g. FOO="abc def") causes first_word
    # to capture only FOO="abc, leaving the quote unmatched. Attempting to strip
    # such a prefix and continue checking the remainder ("def" sed ...) would
    # allow tool-discipline bypass. Block immediately instead.
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
      if [[ "$seg" =~ ^git[[:space:]]+add[[:space:]]+.*\.rnd(/|[[:space:]]|$) ]]; then
        printf 'blocked:BLOCKED: Plugin artifact directories (.rnd/) must never be committed.'
        return 0
      fi

      local _undo_hint="Use \${CLAUDE_PLUGIN_ROOT}/lib/rnd-undo.sh <task_id> for surgical task-scoped reverts."
      local _audit_event_sh="$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh"

      # Emit one gate_fired audit event with the specific op name in the tool slot
      # so downstream analytics can discriminate which destructive op was blocked.
      _emit_destructive_git_block() {
        local _op_name="$1"
        bash "$_audit_event_sh" "gate_fired" "" "destructive_git_blocked:${_op_name}" 2>/dev/null || true
      }

      if [[ "$seg" =~ ^git[[:space:]]+reset[[:space:]]+--hard($|[[:space:]]) ]]; then
        _emit_destructive_git_block "reset_hard"
        printf 'blocked:BLOCKED: git reset --hard destroys working-tree state. %s' "$_undo_hint"
        return 0
      fi

      if [[ "$seg" =~ ^git[[:space:]]+checkout[[:space:]]+\.($|[[:space:]]) ]]; then
        _emit_destructive_git_block "checkout_dot"
        printf 'blocked:BLOCKED: git checkout . discards all working-tree changes. %s' "$_undo_hint"
        return 0
      fi

      if [[ "$seg" =~ ^git[[:space:]]+checkout[[:space:]]+--($|[[:space:]]) ]]; then
        _emit_destructive_git_block "checkout_path"
        printf 'blocked:BLOCKED: git checkout -- <path> discards working-tree changes. %s' "$_undo_hint"
        return 0
      fi

      # git clean: block when the flag argument contains 'f' (or 'F') AND 'd'/'D'/'x'/'X'.
      # A dry-run flag (-n) is not destructive and is allowed.
      if [[ "$seg" =~ ^git[[:space:]]+clean[[:space:]]+ ]]; then
        local _clean_args="${seg#*clean }"
        local _clean_flags=""
        for _a in $_clean_args; do
          if [[ "$_a" == -* ]]; then _clean_flags+="$_a"; fi
        done
        local _has_f=0 _has_fdx=0
        [[ "$_clean_flags" =~ [fF] ]] && _has_f=1
        [[ "$_clean_flags" =~ [dDxX] ]] && _has_fdx=1
        if [[ "$_has_f" -eq 1 && "$_has_fdx" -eq 1 ]]; then
          _emit_destructive_git_block "clean_force"
          printf 'blocked:BLOCKED: git clean with -f and -d/-x permanently deletes untracked files. %s' "$_undo_hint"
          return 0
        fi
      fi

      if [[ "$seg" =~ ^git[[:space:]]+stash[[:space:]]+(drop|clear)($|[[:space:]]) ]]; then
        _emit_destructive_git_block "stash_drop_or_clear"
        printf 'blocked:BLOCKED: git stash drop/clear permanently removes stashed changes. %s' "$_undo_hint"
        return 0
      fi

      if [[ "$seg" =~ ^git[[:space:]]+reflog[[:space:]]+expire($|[[:space:]]) ]]; then
        _emit_destructive_git_block "reflog_expire"
        printf 'blocked:BLOCKED: git reflog expire permanently prunes reachability history. %s' "$_undo_hint"
        return 0
      fi

      if [[ "$seg" =~ ^git[[:space:]]+branch[[:space:]]+-D($|[[:space:]]) ]]; then
        _emit_destructive_git_block "branch_force_delete"
        printf 'blocked:BLOCKED: git branch -D force-deletes a branch without merge check. %s' "$_undo_hint"
        return 0
      fi

      if [[ "$seg" =~ ^git[[:space:]]+worktree[[:space:]]+remove[[:space:]]+--force($|[[:space:]]) ]]; then
        _emit_destructive_git_block "worktree_remove_force"
        printf 'blocked:BLOCKED: git worktree remove --force deletes a worktree without safety checks. %s' "$_undo_hint"
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
_agent_type="$AGENT_TYPE"

if [[ -z "$command" ]]; then exit 0; fi

cmd_lower="$(_lower "$command")"

# ---------------------------------------------------------------------------
# 0. Information barrier — self-assessment files and briefs/ artifacts
# ---------------------------------------------------------------------------
# Blocks any Bash command referencing barrier-protected content (self-assessment
# files OR briefs/ artifacts) when the agent is a verifier or has no declared
# agent_type. Mirrors the barrier in read-gate.sh so that commands like diff,
# jq, less, strings, etc. cannot be used to read protected files around the
# Read tool's guard.

if is_barrier_violation "$command" "$_agent_type"; then
  block_msg "INFORMATION BARRIER: self-assessment files and briefs/ artifacts are records written for the orchestrator and the user — not for the Verifier. Direct reading is blocked to maintain information barriers between Builder and Verifier."
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

_branch_pattern="${_PROTECTED_BRANCHES// /|}"
if [[ "$command" =~ git[[:space:]]+push[[:space:]].*[[:space:]:]($_branch_pattern)([[:space:]]|$) ]]; then
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

if [[ "$cmd_lower" =~ (^|[[:space:];\&\|])for[[:space:]] ]] && [[ "$cmd_lower" =~ (;|[[:space:]])do((;|[[:space:]])|$) ]]; then
  block_msg "Avoid shell for-loops — they frequently hang in the Bash tool. Use the Glob tool to list files and the Grep tool to search content. For cross-referencing, use Grep with alternation patterns or multiple parallel tool calls."
fi

if [[ "$cmd_lower" =~ (^|[[:space:];\&\|])(while|until)[[:space:]] ]] && [[ "$cmd_lower" =~ (;|[[:space:]])do((;|[[:space:]])|$) ]]; then
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
# Tool discipline has already cleared every segment above; the whole-command allow is safe.

if [[ "$command" =~ \.claude[^/]*/.*\.rnd/ ]] || [[ "$command" =~ (^|/)rnd-dir\.sh($|[[:space:]\"\']) ]]; then
  allow_json
  exit 0
fi

plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$plugin_root" ]] && [[ "$command" == *"${plugin_root}/lib/"* ]]; then
  allow_json
  exit 0
fi

# ---------------------------------------------------------------------------
# 7. Bash output cache advisory
# ---------------------------------------------------------------------------
# When the same normalized command was run within RND_BASH_CACHE_TTL_SECONDS
# (default 600s) and produced non-trivial output, advise the agent to Read+Grep
# the cached file instead of re-running. Does not block — agent may still
# proceed if fresh output is needed (e.g. after file changes that affect the
# result). Writer is post-dispatch.sh; the two hooks share cmd_hash semantics
# via lib.sh.

cache_dir="$(bash_cache_dir 2>/dev/null || true)"
if [[ -n "$cache_dir" ]]; then
  cache_key="$(cmd_hash "$command")"
  cache_file="${cache_dir}/${cache_key}.txt"

  if [[ -n "$cache_key" && -f "$cache_file" ]]; then
    cache_mtime="$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || printf '0')"
    now_ts="$(date +%s)"
    cache_age=$((now_ts - cache_mtime))
    cache_ttl="${RND_BASH_CACHE_TTL_SECONDS:-600}"

    if [[ "$cache_age" -ge 0 && "$cache_age" -le "$cache_ttl" ]]; then
      cache_lines="$(wc -l < "$cache_file" 2>/dev/null | tr -d ' ')"
      cache_lines="${cache_lines:-0}"

      if [[ "$cache_lines" -ge 10 ]]; then
        advisory_json "Bash output cache: this exact command ran ${cache_age}s ago; output (${cache_lines} lines) is at ${cache_file}. Use Read + Grep on the cached file to inspect different parts instead of re-running, unless you need fresh output (e.g. after file changes that would affect the result)."
        exit 0
      fi
    fi
  fi
fi

exit 0
