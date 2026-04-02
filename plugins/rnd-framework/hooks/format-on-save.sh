#!/usr/bin/env bash
# hooks/format-on-save.sh — PostToolUse hook for Write and Edit.
#
# Auto-formats code files after Write/Edit operations using the project's
# detected formatter. Enabled by the v2.1.90 fix for "File content has changed"
# errors when PostToolUse hooks rewrite files.
#
# Responsibilities:
#   1. Fast-path exit when no active RND session
#   2. Skip non-code files and .rnd/ artifact paths
#   3. Detect project formatter (cached at session level)
#   4. Run detected formatter on the changed file
#
# Always exits 0. Formatting errors are non-blocking.
#
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---------------------------------------------------------------------------
# Fast-path: skip if no active session
# ---------------------------------------------------------------------------

session_dir="$(active_session_dir 2>/dev/null || true)"
[[ -n "$session_dir" ]] || exit 0

# ---------------------------------------------------------------------------
# Extract file path from PostToolUse input
# ---------------------------------------------------------------------------

raw="$(cat)"
file_path="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"

[[ -n "$file_path" ]] || exit 0

# ---------------------------------------------------------------------------
# Skip non-code files and .rnd/ artifact paths
# ---------------------------------------------------------------------------

if is_plugin_artifact_path "$file_path"; then
  exit 0
fi

if ! is_code_file "$file_path"; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Formatter detection with session-level caching
# ---------------------------------------------------------------------------

readonly CACHE_FILE="${session_dir}/.formatter-cache"

detect_formatter() {
  local project_root
  project_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  # Check config files in priority order (first match wins)
  # Biome
  if [[ -f "${project_root}/biome.json" ]] || [[ -f "${project_root}/biome.jsonc" ]]; then
    printf '{"detected":true,"command":"biome format --write","name":"biome"}'
    return 0
  fi

  # Prettier
  for f in .prettierrc .prettierrc.json .prettierrc.yml .prettierrc.yaml .prettierrc.js .prettierrc.cjs .prettierrc.mjs prettier.config.js prettier.config.cjs prettier.config.mjs prettier.config.ts; do
    if [[ -f "${project_root}/${f}" ]]; then
      printf '{"detected":true,"command":"npx prettier --write","name":"prettier"}'
      return 0
    fi
  done

  # Deno (with fmt key)
  if [[ -f "${project_root}/deno.json" ]]; then
    if jq -e '.fmt' "${project_root}/deno.json" >/dev/null 2>&1; then
      printf '{"detected":true,"command":"deno fmt","name":"deno"}'
      return 0
    fi
  fi

  # Mix (Elixir)
  if [[ -f "${project_root}/mix.exs" ]]; then
    printf '{"detected":true,"command":"mix format","name":"mix"}'
    return 0
  fi

  # Cargo (Rust)
  if [[ -f "${project_root}/Cargo.toml" ]]; then
    printf '{"detected":true,"command":"cargo fmt --","name":"rustfmt"}'
    return 0
  fi

  # Ruff (Python — check before Black)
  if [[ -f "${project_root}/ruff.toml" ]]; then
    printf '{"detected":true,"command":"ruff format","name":"ruff"}'
    return 0
  fi
  if [[ -f "${project_root}/pyproject.toml" ]]; then
    if grep -q '\[tool\.ruff\]' "${project_root}/pyproject.toml" 2>/dev/null; then
      printf '{"detected":true,"command":"ruff format","name":"ruff"}'
      return 0
    fi
    # Black (Python — only if no ruff)
    if grep -q '\[tool\.black\]' "${project_root}/pyproject.toml" 2>/dev/null; then
      printf '{"detected":true,"command":"black","name":"black"}'
      return 0
    fi
  fi

  # Go
  if [[ -f "${project_root}/go.mod" ]]; then
    printf '{"detected":true,"command":"gofmt -w","name":"gofmt"}'
    return 0
  fi

  # Clang-format (C/C++)
  if [[ -f "${project_root}/.clang-format" ]]; then
    printf '{"detected":true,"command":"clang-format -i","name":"clang-format"}'
    return 0
  fi

  # package.json format/fmt script
  if [[ -f "${project_root}/package.json" ]]; then
    local fmt_script
    fmt_script="$(jq -r '.scripts.format // .scripts.fmt // empty' "${project_root}/package.json" 2>/dev/null || true)"
    if [[ -n "$fmt_script" ]]; then
      local runner="npm run"
      if [[ -f "${project_root}/bun.lockb" ]] || [[ -f "${project_root}/bun.lock" ]]; then
        runner="bun run"
      fi
      printf '{"detected":true,"command":"%s format --","name":"package.json"}' "$runner"
      return 0
    fi
  fi

  # No formatter found
  printf '{"detected":false}'
}

# Read or populate cache
formatter_json=""
if [[ -f "$CACHE_FILE" ]]; then
  formatter_json="$(< "$CACHE_FILE")"
else
  formatter_json="$(detect_formatter)"
  printf '%s' "$formatter_json" > "$CACHE_FILE" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Run formatter if detected
# ---------------------------------------------------------------------------

detected="$(printf '%s' "$formatter_json" | jq -r '.detected // false' 2>/dev/null || true)"

if [[ "$detected" != "true" ]]; then
  exit 0
fi

formatter_cmd="$(printf '%s' "$formatter_json" | jq -r '.command // ""' 2>/dev/null || true)"

if [[ -z "$formatter_cmd" ]]; then
  exit 0
fi

# Run formatter on the file — non-blocking (errors do not stop the pipeline)
eval "$formatter_cmd" "$file_path" >/dev/null 2>&1 || true

exit 0
