#!/usr/bin/env bash
# lib/validate-xrefs.sh — Cross-reference and content parity validation.
# Extracted from validate.sh to keep both files under ~250 lines.
#
# INTERFACE: source this file from validate.sh. It expects the following
# functions and variables to be set by the caller:
#   Functions: record_pass, record_fail, emit_info, begin_category, in_array
#   Variables: PLUGIN_ROOT

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

  local s
  while IFS= read -r s; do
    if [[ -n "$s" ]]; then VALID_SKILLS+=("$s"); fi
  done < <(get_valid_skills)

  local agents_dir="${PLUGIN_ROOT}/agents"
  local file fname
  if [[ -d "$agents_dir" ]]; then
    for file in "${agents_dir}"/*.md; do
      if [[ ! -f "$file" ]]; then continue; fi
      fname="${file##*/}"
      VALID_AGENT_REFS+=("rnd-framework:${fname%.md}")
    done
  fi

  for s in "${VALID_SKILLS[@]+"${VALID_SKILLS[@]}"}"; do
    VALID_SKILL_REFS+=("rnd-framework:${s}")
  done

  local cmds_dir="${PLUGIN_ROOT}/commands"
  if [[ -d "$cmds_dir" ]]; then
    for file in "${cmds_dir}"/*.md; do
      if [[ ! -f "$file" ]]; then continue; fi
      fname="${file##*/}"
      VALID_COMMAND_REFS+=("rnd-framework:${fname%.md}")
    done
  fi

  local urfm="${PLUGIN_ROOT}/skills/using-rnd-framework/SKILL.md"
  check_urfm_skill_refs "$urfm"

  if [[ -d "$agents_dir" ]]; then
    for file in "${agents_dir}"/*.md; do
      if [[ ! -f "$file" ]]; then continue; fi
      fname="${file##*/}"
      check_agent_skill_refs "$file" "${fname%.md}"
    done
  fi

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
  "skills/rnd-decomposition/SKILL.md:skills/rnd-orchestration/SKILL.md:External dependencies:pre-registration field"
  "skills/rnd-building/SKILL.md:skills/rnd-build/SKILL.md:erify external dependencies:build step parity"
  "skills/rnd-verification/SKILL.md:skills/rnd-verify/SKILL.md:External contract conformance:failure mode analysis"
  "skills/rnd-verification/SKILL.md:skills/rnd-multi-judge/SKILL.md:ulti-Judge:multi-judge consensus protocol"
  "skills/rnd-decomposition/SKILL.md:commands/rnd-start.md:ocal expert:local expert field parity"
  "skills/rnd-building/SKILL.md:skills/rnd-build/SKILL.md:DONE_WITH_CONCERNS:builder status code DONE_WITH_CONCERNS parity"
  "skills/rnd-building/SKILL.md:skills/rnd-build/SKILL.md:NEEDS_CONTEXT:builder status code NEEDS_CONTEXT parity"
  "skills/rnd-building/SKILL.md:skills/rnd-verification/SKILL.md:Evidence Gathered:evidence gathering parity"
  "skills/rnd-decomposition/SKILL.md:skills/rnd-plan/SKILL.md:Correctness:tiered criteria Correctness marker"
  "skills/rnd-local-experts/SKILL.md:commands/rnd-start.md:.claude/agents/:local expert agents discovery path"
  "skills/rnd-local-experts/SKILL.md:commands/rnd-start.md:.claude/skills/:local expert skills discovery path"
  "skills/rnd-local-experts/SKILL.md:commands/rnd-start.md:Local Experts Discovered:local expert discovery summary field"
  "skills/rnd-local-experts/SKILL.md:skills/rnd-decomposition/SKILL.md:ocal expert:local expert field in decomposition skill"
  "skills/rnd-failure-modes/SKILL.md:skills/rnd-verification/SKILL.md:failure modes:failure modes catalog reference in verification skill"
)

validate_content_parity() {
  begin_category "Content Parity"

  local entry skill_rel agent_rel marker desc parsed
  for entry in "${PARITY_TABLE[@]}"; do
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
