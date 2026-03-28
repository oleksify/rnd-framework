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

VALID_TOOLS=" Read Write Edit Bash Glob Grep Agent AskUserQuestion AskUser TaskCreate TaskUpdate TaskList TaskGet SendMessage WebFetch WebSearch NotebookEdit NotebookRead EnterPlanMode ExitPlanMode EnterWorktree ExitWorktree LSP TeamCreate TeamDelete ToolSearch KillShell BashOutput TaskOutput TaskStop CronCreate CronDelete CronList TodoWrite Skill "

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
# Proofs validation
# ---------------------------------------------------------------------------

validate_proofs() {
  begin_category "Proofs"
  local proofs_dir="${PLUGIN_ROOT}/proofs"
  if [[ ! -d "$proofs_dir" ]]; then
    record_pass "no proofs/ directory (skipped)"
    return 0
  fi
  if ! command -v lean > /dev/null 2>&1 || ! command -v lake > /dev/null 2>&1; then
    record_pass "proofs/ exists (skipped — lean not available)"
    return 0
  fi
  if (cd "$proofs_dir" && lake build 2>/dev/null); then
    record_pass "lake build exits 0 (all proofs compile)"
  else
    record_fail "lake build failed in proofs/"
  fi
}

# ---------------------------------------------------------------------------
# Lib Scripts validation
# ---------------------------------------------------------------------------

validate_lib_scripts() {
  begin_category "Lib Scripts"
  local lib_script script_path
  for lib_script in "rnd-dir.sh" "bump.sh"; do
    script_path="${PLUGIN_ROOT}/lib/${lib_script}"
    if [[ ! -f "$script_path" ]]; then
      record_fail "lib/${lib_script} not found"
      continue
    fi
    record_pass "lib/${lib_script} exists"
    if [[ -x "$script_path" ]]; then
      record_pass "lib/${lib_script} is executable"
    else
      record_fail "lib/${lib_script} is not executable"
    fi
  done
}

# ---------------------------------------------------------------------------
# Cross-reference validation
# ---------------------------------------------------------------------------

get_valid_skills() {
  local skills_dir="${PLUGIN_ROOT}/skills"
  if [[ ! -d "$skills_dir" ]]; then return 0; fi
  local dir name
  for dir in "${skills_dir}"/*/; do
    if [[ ! -d "$dir" ]]; then continue; fi
    name="${dir%/}"
    printf '%s\n' "${name##*/}"
  done
}

check_urfm_skill_refs() {
  local file_path="$1"
  if [[ ! -f "$file_path" ]]; then return 0; fi
  local count=0

  # Extract unique backtick-wrapped rnd-framework:name refs
  local -a refs=()
  while IFS= read -r ref; do
    if [[ -n "$ref" ]]; then refs+=("$ref"); fi
  done < <(
    perl -ne 'while (/`rnd-framework:([a-z-]+)`/g) { print "$1\n" }' "$file_path" \
      | sort -u
  )

  local ref_name full_ref
  for ref_name in "${refs[@]}"; do
    count=$(( count + 1 ))
    full_ref="rnd-framework:${ref_name}"
    if in_array "$ref_name" "${VALID_SKILLS[@]+"${VALID_SKILLS[@]}"}"; then
      record_pass "using-rnd-framework skill ref '${full_ref}' resolves"
    else
      record_fail "using-rnd-framework skill ref '${full_ref}' — skill '${ref_name}' not found"
    fi
  done
  XREF_COUNT=$(( XREF_COUNT + count ))
}

check_agent_skill_refs() {
  local file_path="$1" agent_name="$2"
  if [[ ! -f "$file_path" ]]; then return 0; fi
  local count=0

  # Use perl negative lookbehind to exclude /rnd-framework: URL refs
  local -a refs=()
  while IFS= read -r ref; do
    if [[ -n "$ref" ]]; then refs+=("$ref"); fi
  done < <(
    perl -ne 'while (/(?<![\/])rnd-framework:([a-z-]+)/g) { print "$1\n" }' "$file_path" \
      | sort -u
  )

  local ref_name full_ref
  for ref_name in "${refs[@]}"; do
    count=$(( count + 1 ))
    full_ref="rnd-framework:${ref_name}"
    if in_array "$ref_name" "${VALID_SKILLS[@]+"${VALID_SKILLS[@]}"}"; then
      record_pass "agent '${agent_name}' skill ref '${full_ref}' resolves"
    else
      record_fail "agent '${agent_name}' skill ref '${full_ref}' — skill '${ref_name}' not found"
    fi
  done
  XREF_COUNT=$(( XREF_COUNT + count ))
}

check_command_refs() {
  local file_path="$1" cmd_name="$2"
  if [[ ! -f "$file_path" ]]; then return 0; fi
  local count=0

  local -a refs=()
  while IFS= read -r ref; do
    if [[ -n "$ref" ]]; then refs+=("$ref"); fi
  done < <(
    perl -ne 'while (/rnd-framework:rnd-([a-z-]+)/g) { print "rnd-framework:rnd-$1\n" }' "$file_path" \
      | sort -u
  )

  local full_ref
  for full_ref in "${refs[@]}"; do
    count=$(( count + 1 ))
    if in_array "$full_ref" "${VALID_AGENT_REFS[@]+"${VALID_AGENT_REFS[@]}"}"; then
      record_pass "command '${cmd_name}' agent ref '${full_ref}' resolves"
    elif in_array "$full_ref" "${VALID_SKILL_REFS[@]+"${VALID_SKILL_REFS[@]}"}"; then
      record_pass "command '${cmd_name}' skill ref '${full_ref}' resolves"
    elif in_array "$full_ref" "${VALID_COMMAND_REFS[@]+"${VALID_COMMAND_REFS[@]}"}"; then
      record_pass "command '${cmd_name}' command ref '${full_ref}' resolves"
    else
      record_fail "command '${cmd_name}' ref '${full_ref}' — not found as agent, skill, or command"
    fi
  done
  XREF_COUNT=$(( XREF_COUNT + count ))
}

XREF_COUNT=0
declare -a VALID_SKILLS=()
declare -a VALID_AGENT_REFS=()
declare -a VALID_SKILL_REFS=()
declare -a VALID_COMMAND_REFS=()

validate_cross_refs() {
  begin_category "Cross-References"
  XREF_COUNT=0

  # Build valid skills list
  local s
  while IFS= read -r s; do
    if [[ -n "$s" ]]; then VALID_SKILLS+=("$s"); fi
  done < <(get_valid_skills)

  # Build valid agent refs list
  local agents_dir="${PLUGIN_ROOT}/agents"
  local file fname
  if [[ -d "$agents_dir" ]]; then
    for file in "${agents_dir}"/*.md; do
      if [[ ! -f "$file" ]]; then continue; fi
      fname="${file##*/}"
      VALID_AGENT_REFS+=("rnd-framework:${fname%.md}")
    done
  fi

  # Build valid skill refs list
  for s in "${VALID_SKILLS[@]+"${VALID_SKILLS[@]}"}"; do
    VALID_SKILL_REFS+=("rnd-framework:${s}")
  done

  # Build valid command refs list
  local cmds_dir="${PLUGIN_ROOT}/commands"
  if [[ -d "$cmds_dir" ]]; then
    for file in "${cmds_dir}"/*.md; do
      if [[ ! -f "$file" ]]; then continue; fi
      fname="${file##*/}"
      VALID_COMMAND_REFS+=("rnd-framework:${fname%.md}")
    done
  fi

  # Check using-rnd-framework skill refs
  local urfm="${PLUGIN_ROOT}/skills/using-rnd-framework/SKILL.md"
  check_urfm_skill_refs "$urfm"

  # Check agent skill refs
  if [[ -d "$agents_dir" ]]; then
    for file in "${agents_dir}"/*.md; do
      if [[ ! -f "$file" ]]; then continue; fi
      fname="${file##*/}"
      check_agent_skill_refs "$file" "${fname%.md}"
    done
  fi

  # Check command refs
  if [[ -d "$cmds_dir" ]]; then
    for file in "${cmds_dir}"/*.md; do
      if [[ ! -f "$file" ]]; then continue; fi
      fname="${file##*/}"
      check_command_refs "$file" "${fname%.md}"
    done
  fi

  emit_info "  (${XREF_COUNT} cross-references checked)"
}

# ---------------------------------------------------------------------------
# Content Parity validation
# ---------------------------------------------------------------------------

PARITY_TABLE=(
  # Decomposition ↔ Orchestration: pre-registration format
  "skills/rnd-decomposition/SKILL.md:skills/rnd-orchestration/SKILL.md:External dependencies:pre-registration field"
  # Building ↔ Build command: verify external dependencies
  "skills/rnd-building/SKILL.md:commands/rnd-build.md:erify external dependencies:build step parity"
  # Verification ↔ Verify command: external contract conformance
  "skills/rnd-verification/SKILL.md:commands/rnd-verify.md:External contract conformance:failure mode analysis"
  # Verification ↔ Multi-judge: multi-judge protocol reference
  "skills/rnd-verification/SKILL.md:skills/rnd-multi-judge/SKILL.md:ulti-Judge:multi-judge consensus protocol"
  # Decomposition ↔ Start command: local expert field
  "skills/rnd-decomposition/SKILL.md:commands/rnd-start.md:ocal expert:local expert field parity"
  # Building ↔ Build command: status codes
  "skills/rnd-building/SKILL.md:commands/rnd-build.md:DONE_WITH_CONCERNS:builder status code DONE_WITH_CONCERNS parity"
  "skills/rnd-building/SKILL.md:commands/rnd-build.md:NEEDS_CONTEXT:builder status code NEEDS_CONTEXT parity"
  # Building ↔ Verification: evidence gathered cross-reference
  "skills/rnd-building/SKILL.md:skills/rnd-verification/SKILL.md:Evidence Gathered:evidence gathering parity"
  # Decomposition ↔ Plan command: tiered criteria
  "skills/rnd-decomposition/SKILL.md:commands/rnd-plan.md:Correctness:tiered criteria Correctness marker"
  # Local experts ↔ Start command
  "skills/rnd-local-experts/SKILL.md:commands/rnd-start.md:.claude/agents/:local expert agents discovery path"
  "skills/rnd-local-experts/SKILL.md:commands/rnd-start.md:.claude/skills/:local expert skills discovery path"
  "skills/rnd-local-experts/SKILL.md:commands/rnd-start.md:Local Experts Discovered:local expert discovery summary field"
  # Local experts ↔ Decomposition
  "skills/rnd-local-experts/SKILL.md:skills/rnd-decomposition/SKILL.md:ocal expert:local expert field in decomposition skill"
  # Failure modes ↔ Verification
  "skills/rnd-failure-modes/SKILL.md:skills/rnd-verification/SKILL.md:failure modes:failure modes catalog reference in verification skill"
)

validate_content_parity() {
  begin_category "Content Parity"

  local entry skill_rel agent_rel marker desc parsed
  for entry in "${PARITY_TABLE[@]}"; do
    # Parse: skill_rel:agent_rel:marker:desc
    # marker may contain ':' (e.g., "Correctness:"), so we parse from ends
    parsed="$(awk -F: -v OFS='\t' '{
      skill=$1; agent=$2;
      n=NF; desc=$n;
      marker="";
      for(i=3;i<n;i++) marker=(i==3)?$i:(marker":"$i);
      print skill, agent, marker, desc
    }' <<< "$entry")"

    skill_rel="$(printf '%s' "$parsed" | cut -f1)"
    agent_rel="$(printf '%s' "$parsed" | cut -f2)"
    marker="$(printf '%s' "$parsed" | cut -f3)"
    desc="$(printf '%s' "$parsed" | cut -f4)"

    local skill_file="${PLUGIN_ROOT}/${skill_rel}"
    local agent_file="${PLUGIN_ROOT}/${agent_rel}"

    # Extract display names
    local skill_name agent_name
    skill_name="${skill_rel%/SKILL.md}"
    skill_name="${skill_name##*/}"
    if [[ "$agent_rel" == skills/* ]]; then
      agent_name="${agent_rel%/SKILL.md}"
      agent_name="${agent_name##*/}"
    else
      agent_name="${agent_rel##*/}"
      agent_name="${agent_name%.md}"
    fi

    local marker_lower
    marker_lower="$(printf '%s' "$marker" | tr '[:upper:]' '[:lower:]')"

    local skill_has=false agent_has=false
    if [[ -f "$skill_file" ]]; then
      local skill_content_lower
      skill_content_lower="$(tr '[:upper:]' '[:lower:]' < "$skill_file")"
      if [[ "$skill_content_lower" == *"$marker_lower"* ]]; then skill_has=true; fi
    fi
    if [[ -f "$agent_file" ]]; then
      local agent_content_lower
      agent_content_lower="$(tr '[:upper:]' '[:lower:]' < "$agent_file")"
      if [[ "$agent_content_lower" == *"$marker_lower"* ]]; then agent_has=true; fi
    fi

    if [[ "$skill_has" == "true" && "$agent_has" == "true" ]]; then
      record_pass "parity: '${marker}' in ${skill_name} and ${agent_name} (${desc})"
    elif [[ "$skill_has" == "true" && "$agent_has" == "false" ]]; then
      record_fail "parity: '${marker}' in ${skill_name} but missing in ${agent_name}"
    elif [[ "$skill_has" == "false" && "$agent_has" == "true" ]]; then
      record_fail "parity: '${marker}' in ${agent_name} but missing in ${skill_name}"
    else
      record_fail "parity: '${marker}' missing in both ${skill_name} and ${agent_name}"
    fi
  done
}

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
validate_proofs
validate_lib_scripts
validate_cross_refs
validate_content_parity
build_summary

# Print all output
for line in "${OUTPUT_LINES[@]}"; do
  printf '%s\n' "$line"
done

if [[ "$ERRORS" -eq 0 ]]; then exit 0; else exit 1; fi
