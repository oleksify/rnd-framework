#!/usr/bin/env bash
# hooks/db-guard.sh — PreToolUse hook for Bash: blocks destructive database operations.
#
# Prevents accidental destruction of development databases by blocking:
# - Ecto reset/drop without MIX_ENV=test
# - Direct deletion of database files (.db, .sqlite, .sqlite3)
# - PostgreSQL destructive commands (dropdb, DROP DATABASE, pg_restore --clean)
# - MySQL destructive commands (mysqladmin drop, DROP DATABASE)
# - SQLite destructive SQL (DELETE FROM, DROP TABLE, DROP INDEX)
#
# Advisory warnings for dev database ecto.create/ecto.migrate.
#
# Exit codes:
#   0 + no stdout               — no opinion
#   0 + advisory JSON           — warning (does not block)
#   2 + stderr message          — blocked
#
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

raw="$(cat)"
command="$(printf '%s' "$raw" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"

# Empty or malformed input — no opinion
if [[ -z "$command" ]]; then exit 0; fi

# Lowercase version for case-insensitive matching
cmd_lower="${command,,}"

# ---------------------------------------------------------------------------
# 1. Ecto destructive commands without MIX_ENV=test
# ---------------------------------------------------------------------------

if [[ "$cmd_lower" == *"mix ecto.reset"* ]] || [[ "$cmd_lower" == *"mix ecto.drop"* ]]; then
  if [[ "$cmd_lower" != *"mix_env=test"* ]]; then
    block_msg "BLOCKED: \`mix ecto.reset\` destroys the dev database. Only MIX_ENV=test is allowed for destructive Ecto commands."
  fi
fi

# ---------------------------------------------------------------------------
# 2. Direct database file deletion
# ---------------------------------------------------------------------------

if [[ "$cmd_lower" =~ rm[[:space:]] ]]; then
  if [[ "$cmd_lower" =~ \.(db|sqlite|sqlite3)([[:space:]]|$) ]]; then
    block_msg "BLOCKED: Refusing to delete database file. Database files (.db, .sqlite, .sqlite3) are protected."
  fi
fi

# ---------------------------------------------------------------------------
# 3. PostgreSQL destructive commands
# ---------------------------------------------------------------------------

# dropdb CLI tool
if [[ "$cmd_lower" =~ (^|[[:space:];&|])dropdb([[:space:]]|$) ]]; then
  block_msg "BLOCKED: Destructive PostgreSQL operation. Use MIX_ENV=test for test databases only."
fi

# psql -c "DROP DATABASE ..."
if [[ "$cmd_lower" =~ psql.*-c.*drop[[:space:]]+database ]]; then
  block_msg "BLOCKED: Destructive PostgreSQL operation. Use MIX_ENV=test for test databases only."
fi

# pg_restore --clean
if [[ "$cmd_lower" =~ pg_restore.*--clean ]]; then
  block_msg "BLOCKED: Destructive PostgreSQL operation. Use MIX_ENV=test for test databases only."
fi

# ---------------------------------------------------------------------------
# 4. MySQL destructive commands
# ---------------------------------------------------------------------------

# mysqladmin drop
if [[ "$cmd_lower" =~ mysqladmin.*drop ]]; then
  block_msg "BLOCKED: Destructive MySQL operation. Use test databases only."
fi

# mysql -e "DROP DATABASE ..."
if [[ "$cmd_lower" =~ mysql[[:space:]].*-e.*drop[[:space:]]+database ]]; then
  block_msg "BLOCKED: Destructive MySQL operation. Use test databases only."
fi

# ---------------------------------------------------------------------------
# 5. SQLite destructive SQL via CLI
# ---------------------------------------------------------------------------

if [[ "$cmd_lower" =~ sqlite3[[:space:]] ]]; then
  if [[ "$cmd_lower" =~ (delete[[:space:]]+from|drop[[:space:]]+table|drop[[:space:]]+index) ]]; then
    block_msg "BLOCKED: Destructive SQLite SQL. Use application code for data modifications."
  fi
fi

# ---------------------------------------------------------------------------
# 6. Advisory warnings for dev database operations
# ---------------------------------------------------------------------------

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
# No opinion — let other hooks and permission system handle it
# ---------------------------------------------------------------------------

exit 0
