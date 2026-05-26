#!/usr/bin/env bash
# lib/validate.sh — Plugin structure validation (bash port of validate.ts)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${SCRIPT_DIR}/.."

QUIET=false
for arg in "$@"; do
  if [[ "$arg" == "--quiet" ]]; then QUIET=true; fi
done

# ---------------------------------------------------------------------------
# Tracking state
# ---------------------------------------------------------------------------

PASSES=0
ERRORS=0
OUTPUT_LINES=()
declare -a CAT_NAMES=()
declare -a CAT_PASS=()
declare -a CAT_FAIL=()

begin_category() {
  local name="$1"
  if [[ ${#CAT_NAMES[@]} -gt 0 ]] && [[ "$QUIET" == "false" ]]; then
    OUTPUT_LINES+=("")
  fi
  CAT_NAMES+=("$name")
  CAT_PASS+=(0)
  CAT_FAIL+=(0)
  if [[ "$QUIET" == "false" ]]; then
    OUTPUT_LINES+=("=== ${name} ===")
  fi
}

record_pass() {
  local msg="$1"
  PASSES=$(( PASSES + 1 ))
  local idx=$(( ${#CAT_NAMES[@]} - 1 ))
  CAT_PASS[$idx]=$(( ${CAT_PASS[$idx]} + 1 ))
  if [[ "$QUIET" == "false" ]]; then
    OUTPUT_LINES+=("  PASS  ${msg}")
  fi
}

record_fail() {
  local msg="$1"
  ERRORS=$(( ERRORS + 1 ))
  local idx=$(( ${#CAT_NAMES[@]} - 1 ))
  CAT_FAIL[$idx]=$(( ${CAT_FAIL[$idx]} + 1 ))
  if [[ "$QUIET" == "false" ]]; then
    OUTPUT_LINES+=("  FAIL  ${msg}")
  fi
}

emit_info() {
  OUTPUT_LINES+=("$1")
}

# ---------------------------------------------------------------------------
# Array membership helper
# ---------------------------------------------------------------------------

in_array() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then return 0; fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Frontmatter extraction
# ---------------------------------------------------------------------------

frontmatter_val() {
  local file="$1" key="$2"
  if [[ ! -f "$file" ]]; then printf ''; return 0; fi
  awk -v key="$key" '
    /^---$/ { fm++; next }
    fm==1 && $0 ~ "^"key":" {
      sub("^"key":[ ]*", "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      print
      exit
    }
    fm>=2 { exit }
  ' "$file"
}

# ---------------------------------------------------------------------------
# VALID_TOOLS set
# ---------------------------------------------------------------------------

VALID_TOOLS=" Read Write Edit Bash Glob Grep Agent AskUserQuestion TaskCreate TaskUpdate TaskList TaskGet SendMessage WebFetch WebSearch NotebookEdit NotebookRead EnterPlanMode ExitPlanMode EnterWorktree ExitWorktree LSP TeamCreate TeamDelete ToolSearch KillShell BashOutput TaskOutput TaskStop CronCreate CronDelete CronList TodoWrite Skill "

is_valid_tool() {
  [[ " $VALID_TOOLS " == *" $1 "* ]]
}

# ---------------------------------------------------------------------------
# Manifest validation
# ---------------------------------------------------------------------------

validate_manifest() {
  begin_category "Manifest"
  local pjson="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
  if [[ ! -f "$pjson" ]]; then
    record_fail "plugin.json not found at ${pjson}"
    return 0
  fi
  local parsed
  if ! parsed="$(jq -e . < "$pjson" 2>/dev/null)"; then
    record_fail "plugin.json is not valid JSON"
    return 0
  fi
  record_pass "plugin.json is valid JSON"

  local field val
  for field in name description version; do
    val="$(jq -r --arg f "$field" '.[$f] // empty' <<< "$parsed" 2>/dev/null || true)"
    if [[ -n "$val" ]]; then
      record_pass "plugin.json has '${field}': ${val}"
    else
      record_fail "plugin.json missing '${field}'"
    fi
  done

  local ver
  ver="$(jq -r '.version // empty' <<< "$parsed" 2>/dev/null || true)"
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    record_pass "plugin.json version is valid semver"
  else
    record_fail "plugin.json version '${ver}' is not valid semver (expected X.Y.Z)"
  fi
}

# ---------------------------------------------------------------------------
# Hooks validation
# ---------------------------------------------------------------------------

validate_hooks() {
  begin_category "Hooks"
  local hjson="${PLUGIN_ROOT}/hooks/hooks.json"
  if [[ ! -f "$hjson" ]]; then
    record_fail "hooks.json not found at ${hjson}"
    return 0
  fi
  if ! jq -e . < "$hjson" > /dev/null 2>&1; then
    record_fail "hooks.json is not valid JSON"
    return 0
  fi
  record_pass "hooks.json is valid JSON"

  # Extract unique hook script references matching hooks/[a-z_.-]+
  local -a refs=()
  while IFS= read -r ref; do
    if [[ -n "$ref" ]]; then refs+=("$ref"); fi
  done < <(
    perl -ne 'while (/hooks\/([a-z_.-]+)/g) { print "hooks/$1\n" }' "$hjson" | sort -u
  )

  local ref script_path name
  for ref in "${refs[@]}"; do
    script_path="${PLUGIN_ROOT}/${ref}"
    name="${ref##*/}"
    if [[ ! -f "$script_path" ]]; then
      record_fail "hook script '${name}' not found at ${script_path}"
      continue
    fi
    record_pass "hook script '${name}' exists"
    if [[ -x "$script_path" ]]; then
      record_pass "hook script '${name}' is executable"
    else
      record_fail "hook script '${name}' is not executable"
    fi
  done
}

# ---------------------------------------------------------------------------
# Skills validation
# ---------------------------------------------------------------------------

validate_skills() {
  begin_category "Skills"
  local skills_dir="${PLUGIN_ROOT}/skills"
  local count=0
  if [[ ! -d "$skills_dir" ]]; then
    emit_info "  (0 skills found)"
    return 0
  fi

  local dir dir_name skill_file first_line name_val desc_val
  for dir in "${skills_dir}"/*/; do
    if [[ ! -d "$dir" ]]; then continue; fi
    dir_name="${dir%/}"
    dir_name="${dir_name##*/}"
    skill_file="${skills_dir}/${dir_name}/SKILL.md"

    if [[ ! -f "$skill_file" ]]; then
      record_fail "skill '${dir_name}' missing SKILL.md"
      continue
    fi
    count=$(( count + 1 ))

    IFS= read -r first_line < "$skill_file" || true
    if [[ "$first_line" != "---" ]]; then
      record_fail "skill '${dir_name}' missing frontmatter (no opening ---)"
      continue
    fi

    name_val="$(frontmatter_val "$skill_file" "name")"
    desc_val="$(frontmatter_val "$skill_file" "description")"

    if [[ -z "$name_val" ]]; then
      record_fail "skill '${dir_name}' missing 'name' in frontmatter"
    elif [[ "$name_val" == "$dir_name" ]]; then
      record_pass "skill '${dir_name}' name matches directory"
    else
      record_fail "skill '${dir_name}' name mismatch: frontmatter says '${name_val}'"
    fi

    if [[ -n "$desc_val" ]]; then
      record_pass "skill '${dir_name}' has description"
    else
      record_fail "skill '${dir_name}' missing 'description' in frontmatter"
    fi
  done

  emit_info "  (${count} skills found)"
}

# ---------------------------------------------------------------------------
# Agents validation
# ---------------------------------------------------------------------------

check_tools_field() {
  local agent_name="$1" tools_val="$2"
  local all_valid=true
  local IFS_SAVE="$IFS"
  IFS=', '
  local -a tools=()
  read -ra tools <<< "$tools_val" || true
  IFS="$IFS_SAVE"

  local tool
  for tool in "${tools[@]}"; do
    if [[ -z "$tool" ]]; then continue; fi
    if ! is_valid_tool "$tool"; then
      record_fail "agent '${agent_name}' has unknown tool '${tool}'"
      all_valid=false
    fi
  done
  if [[ "$all_valid" == "true" ]]; then
    record_pass "agent '${agent_name}' tools are valid: ${tools_val}"
  fi
}

check_disallowed_tools_field() {
  local agent_name="$1" val="$2"
  local all_valid=true
  local IFS_SAVE="$IFS"
  IFS=', '
  local -a tools=()
  read -ra tools <<< "$val" || true
  IFS="$IFS_SAVE"

  local tool
  for tool in "${tools[@]}"; do
    if [[ -z "$tool" ]]; then continue; fi
    if ! is_valid_tool "$tool"; then
      record_fail "agent '${agent_name}' has unknown disallowed tool '${tool}'"
      all_valid=false
    fi
  done
  if [[ "$all_valid" == "true" ]]; then
    record_pass "agent '${agent_name}' disallowedTools are valid: ${val}"
  fi
}

validate_one_agent() {
  local file_path="$1" agent_name="$2"

  local first_line
  IFS= read -r first_line < "$file_path" || true
  if [[ "$first_line" != "---" ]]; then
    record_fail "agent '${agent_name}' missing frontmatter"
    return 0
  fi

  local name_val desc_val tools_val model_val
  name_val="$(frontmatter_val "$file_path" "name")"
  desc_val="$(frontmatter_val "$file_path" "description")"
  tools_val="$(frontmatter_val "$file_path" "tools")"
  model_val="$(frontmatter_val "$file_path" "model")"

  if [[ "$name_val" == "$agent_name" ]]; then
    record_pass "agent '${agent_name}' name matches filename"
  elif [[ -n "$name_val" ]]; then
    record_fail "agent '${agent_name}' name mismatch: frontmatter says '${name_val}'"
  else
    record_fail "agent '${agent_name}' missing 'name'"
  fi

  if [[ -n "$desc_val" ]]; then
    record_pass "agent '${agent_name}' has description"
  else
    record_fail "agent '${agent_name}' missing 'description'"
  fi

  if [[ -n "$tools_val" ]]; then
    check_tools_field "$agent_name" "$tools_val"
  else
    record_fail "agent '${agent_name}' missing 'tools'"
  fi

  if [[ -n "$model_val" ]]; then
    if [[ "$model_val" == "opus" || "$model_val" == "sonnet" || "$model_val" == "haiku" ]]; then
      record_pass "agent '${agent_name}' model is valid: ${model_val}"
    else
      record_fail "agent '${agent_name}' has unknown model '${model_val}'"
    fi
  else
    record_fail "agent '${agent_name}' missing 'model'"
  fi

  # Optional fields
  local memory_val
  memory_val="$(frontmatter_val "$file_path" "memory")"
  if [[ -n "$memory_val" ]]; then
    if [[ "$memory_val" == "user" || "$memory_val" == "project" || "$memory_val" == "local" ]]; then
      record_pass "agent '${agent_name}' memory scope is valid: ${memory_val}"
    else
      record_fail "agent '${agent_name}' has invalid memory scope '${memory_val}'"
    fi
  fi

  local color_val
  color_val="$(frontmatter_val "$file_path" "color")"
  if [[ -n "$color_val" ]]; then
    record_pass "agent '${agent_name}' has color: ${color_val}"
  fi

  local skills_val
  skills_val="$(frontmatter_val "$file_path" "skills")"
  if [[ -n "$skills_val" ]]; then
    record_pass "agent '${agent_name}' has skills: ${skills_val}"
  fi

  local disallowed_val
  disallowed_val="$(frontmatter_val "$file_path" "disallowedTools")"
  if [[ -n "$disallowed_val" ]]; then
    check_disallowed_tools_field "$agent_name" "$disallowed_val"
  fi

  local perm_val
  perm_val="$(frontmatter_val "$file_path" "permissionMode")"
  if [[ -n "$perm_val" ]]; then
    if [[ "$perm_val" == "bypassPermissions" ]]; then
      record_pass "agent '${agent_name}' permissionMode is valid: ${perm_val}"
    else
      record_fail "agent '${agent_name}' has invalid permissionMode '${perm_val}'"
    fi
  fi
}

validate_agents() {
  begin_category "Agents"
  local agents_dir="${PLUGIN_ROOT}/agents"
  local count=0
  if [[ ! -d "$agents_dir" ]]; then
    emit_info "  (0 agents found)"
    return 0
  fi

  local file filename agent_name
  for file in "${agents_dir}"/*.md; do
    if [[ ! -f "$file" ]]; then continue; fi
    count=$(( count + 1 ))
    filename="${file##*/}"
    agent_name="${filename%.md}"
    validate_one_agent "$file" "$agent_name"
  done

  emit_info "  (${count} agents found)"
}

# ---------------------------------------------------------------------------
# Commands validation
# ---------------------------------------------------------------------------

validate_commands() {
  begin_category "Commands"
  local cmds_dir="${PLUGIN_ROOT}/commands"
  local count=0
  if [[ ! -d "$cmds_dir" ]]; then
    emit_info "  (0 commands found)"
    return 0
  fi

  local file filename cmd_name first_line desc_val content uses_args hint_val model_val
  for file in "${cmds_dir}"/*.md; do
    if [[ ! -f "$file" ]]; then continue; fi
    count=$(( count + 1 ))
    filename="${file##*/}"
    cmd_name="${filename%.md}"

    IFS= read -r first_line < "$file" || true
    if [[ "$first_line" != "---" ]]; then
      record_fail "command '${cmd_name}' missing frontmatter"
      continue
    fi

    desc_val="$(frontmatter_val "$file" "description")"
    if [[ -n "$desc_val" ]]; then
      record_pass "command '${cmd_name}' has description"
    else
      record_fail "command '${cmd_name}' missing 'description'"
    fi

    content="$(< "$file")"
    uses_args=false
    if [[ "$content" == *'$ARGUMENTS'* ]]; then uses_args=true; fi

    hint_val="$(frontmatter_val "$file" "argument-hint")"

    if [[ "$uses_args" == "true" && -z "$hint_val" ]]; then
      record_fail "command '${cmd_name}' uses \$ARGUMENTS but missing 'argument-hint'"
    elif [[ "$uses_args" == "false" && -n "$hint_val" ]]; then
      record_fail "command '${cmd_name}' has 'argument-hint' but never uses \$ARGUMENTS"
    elif [[ "$uses_args" == "true" && -n "$hint_val" ]]; then
      record_pass "command '${cmd_name}' has argument-hint"
    fi

    model_val="$(frontmatter_val "$file" "model")"
    if [[ -n "$model_val" ]]; then
      if [[ "$model_val" == "opus" || "$model_val" == "sonnet" || "$model_val" == "haiku" ]]; then
        record_pass "command '${cmd_name}' model is valid: ${model_val}"
      else
        record_fail "command '${cmd_name}' has invalid model '${model_val}'"
      fi
    fi
  done

  emit_info "  (${count} commands found)"
}

# ---------------------------------------------------------------------------
# Output Styles validation
# ---------------------------------------------------------------------------

validate_output_styles() {
  begin_category "Output Styles"
  local styles_dir="${PLUGIN_ROOT}/output-styles"
  local count=0
  if [[ ! -d "$styles_dir" ]]; then
    emit_info "  (0 output styles found)"
    return 0
  fi

  local file filename style_name first_line name_val desc_val
  for file in "${styles_dir}"/*.md; do
    if [[ ! -f "$file" ]]; then continue; fi
    count=$(( count + 1 ))
    filename="${file##*/}"
    style_name="${filename%.md}"

    IFS= read -r first_line < "$file" || true
    if [[ "$first_line" != "---" ]]; then
      record_fail "output-style '${style_name}' missing frontmatter"
      continue
    fi

    name_val="$(frontmatter_val "$file" "name")"
    if [[ -n "$name_val" ]]; then
      record_pass "output-style '${style_name}' has name: ${name_val}"
    else
      record_fail "output-style '${style_name}' missing 'name'"
    fi

    desc_val="$(frontmatter_val "$file" "description")"
    if [[ -n "$desc_val" ]]; then
      record_pass "output-style '${style_name}' has description"
    else
      record_fail "output-style '${style_name}' missing 'description'"
    fi
  done

  emit_info "  (${count} output styles found)"
}

# ---------------------------------------------------------------------------
# Lib Scripts validation
# ---------------------------------------------------------------------------

validate_lib_scripts() {
  begin_category "Lib Scripts"
  # Scripts that are meant to be sourced rather than executed directly.
  # Their interface contract is documented in their header.
  local sourced_only=" plugin-dir-base.sh validate-xrefs.sh "
  local script_path script_name
  for script_path in "${PLUGIN_ROOT}/lib/"*.sh; do
    [[ -f "$script_path" ]] || continue
    script_name="${script_path##*/}"
    record_pass "lib/${script_name} exists"
    if [[ "$sourced_only" == *" ${script_name} "* ]]; then
      continue
    fi
    if [[ -x "$script_path" ]]; then
      record_pass "lib/${script_name} is executable"
    else
      record_fail "lib/${script_name} is not executable"
    fi
  done

  # Parity check: root lib copy must match the rnd-framework plugin copy
  local root_copy="${PLUGIN_ROOT}/../../lib/plugin-dir-base.sh"
  local plugin_copy="${PLUGIN_ROOT}/lib/plugin-dir-base.sh"
  if [[ ! -f "$root_copy" ]]; then
    record_pass "lib/plugin-dir-base.sh root copy not present — skipping parity check"
  elif diff -q "$root_copy" "$plugin_copy" > /dev/null 2>&1; then
    record_pass "lib/plugin-dir-base.sh copies are identical"
  else
    record_fail "lib/plugin-dir-base.sh root copy differs from plugin copy — run: diff ${root_copy} ${plugin_copy}"
  fi

  # 3-way parity: tight-loop copy must also match root lib copy
  local tight_copy="${PLUGIN_ROOT}/../../plugins/tight-loop/lib/plugin-dir-base.sh"
  if [[ ! -f "$root_copy" ]]; then
    record_pass "lib/plugin-dir-base.sh root copy not present — skipping tight-loop parity check"
  elif [[ ! -f "$tight_copy" ]]; then
    record_pass "plugins/tight-loop/lib/plugin-dir-base.sh not present — skipping tight-loop parity check"
  elif diff -q "$root_copy" "$tight_copy" > /dev/null 2>&1; then
    record_pass "lib/plugin-dir-base.sh tight-loop copy is identical to root"
  else
    record_fail "lib/plugin-dir-base.sh tight-loop copy differs from root — run: diff ${root_copy} ${tight_copy}"
  fi
}

# ---------------------------------------------------------------------------
# Cross-reference and content parity (extracted to lib/validate-xrefs.sh)
# ---------------------------------------------------------------------------

# shellcheck source=validate-xrefs.sh
source "${SCRIPT_DIR}/validate-xrefs.sh"

# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------

build_summary() {
  OUTPUT_LINES+=("")
  OUTPUT_LINES+=("=== Summary ===")
  OUTPUT_LINES+=("")

  OUTPUT_LINES+=("$(printf '  %-20s %6s %6s   %s' "Category" "Pass" "Fail" "Status")")
  OUTPUT_LINES+=("$(printf '  %-20s %6s %6s   %s' "────────────────────" "──────" "──────" "──────")")

  local i cat_name p f status
  for (( i=0; i<${#CAT_NAMES[@]}; i++ )); do
    cat_name="${CAT_NAMES[$i]}"
    p="${CAT_PASS[$i]}"
    f="${CAT_FAIL[$i]}"
    if [[ "$f" -gt 0 ]]; then status="FAIL"; else status="ok"; fi
    OUTPUT_LINES+=("$(printf '  %-20s %6s %6s   %s' "$cat_name" "$p" "$f" "$status")")
  done

  OUTPUT_LINES+=("$(printf '  %-20s %6s %6s' "────────────────────" "──────" "──────")")
  OUTPUT_LINES+=("$(printf '  %-20s %6s %6s' "Total" "$PASSES" "$ERRORS")")
  OUTPUT_LINES+=("")

  if [[ "$ERRORS" -gt 0 ]]; then
    OUTPUT_LINES+=("  ${ERRORS} check(s) failed.")
  else
    OUTPUT_LINES+=("  All ${PASSES} checks passed.")
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

validate_manifest
validate_hooks
validate_skills
validate_agents
validate_commands
validate_output_styles
validate_lib_scripts
validate_cross_refs
validate_content_parity
build_summary

# Print all output
for line in "${OUTPUT_LINES[@]}"; do
  printf '%s\n' "$line"
done

if [[ "$ERRORS" -eq 0 ]]; then exit 0; else exit 1; fi
