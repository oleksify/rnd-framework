#!/usr/bin/env bash
# hooks/bash-gate.sh — Unified PreToolUse hook for Bash/Execute.
#
# Merged from db-guard.sh + prefer-tools.sh into a single dispatcher.
# Fast-path: exits immediately when no active RND session.
#
# Responsibilities:
#   1. Information barrier — blocks self-assessment/briefs/cleanup reads for rnd-verifier/rnd-polisher
#   2. Database guard — blocks destructive DB operations (Ecto, Postgres, MySQL, SQLite)
#   3. Git guards — blocks git add .rnd/, destructive git ops; advisory on git push to protected branches
#   4. Auto-allow — .rnd/ paths and plugin lib scripts
#   5. Bash output cache advisory
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
readonly _PROTECTED_BRANCHES="main master production"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

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
  esac
  printf 'allowed'
}

split_and_check() {
  local command="$1"
  local _result

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
  done <<< "$split_cmd"

  printf 'allowed'
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
# files OR briefs/ / cleanup/ artifacts) when the agent is rnd-verifier or
# rnd-polisher. Empty agent_type (orchestrator) is intentionally NOT blocked —
# the orchestrator relays these artifacts to the user. Mirrors the barrier in
# read-gate.sh and lib.sh::is_barrier_violation so that commands like diff, jq,
# less, strings, etc. cannot be used to read protected files around the Read
# tool's guard.

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
# 3. Per-segment git checks (git add .rnd/ and destructive git ops)
# ---------------------------------------------------------------------------

_git_block_result="$(split_and_check "$command")" || true

if [[ "$_git_block_result" == blocked:* ]]; then
  block_msg "${_git_block_result#blocked:}"
fi

# ---------------------------------------------------------------------------
# 4. Auto-allow plugin artifact paths and lib scripts
# ---------------------------------------------------------------------------

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
# 5. Bash output cache advisory
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
