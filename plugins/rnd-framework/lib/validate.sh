#!/usr/bin/env bash
# Validates rnd-framework plugin structure: frontmatter, JSON files, hook references.
# Exits 0 if all checks pass, 1 if any fail.
#
# Flags:
#   --quiet   Suppress individual checks, show only summary table + exit code

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

QUIET=false
if [ "${1:-}" = "--quiet" ]; then
  QUIET=true
fi

ERRORS=0
PASSES=0

# Per-category counters (parallel arrays)
CAT_NAMES=()
CAT_PASS=()
CAT_FAIL=()
CURRENT_CAT=""

begin_category() {
  CURRENT_CAT="$1"
  CAT_NAMES+=("$1")
  CAT_PASS+=(0)
  CAT_FAIL+=(0)
  if ! $QUIET; then
    [ ${#CAT_NAMES[@]} -gt 1 ] && echo ""
    echo "=== $1 ==="
  fi
}

pass() {
  $QUIET || echo "  PASS  $1"
  PASSES=$((PASSES + 1))
  local i=$(( ${#CAT_PASS[@]} - 1 ))
  CAT_PASS[$i]=$(( ${CAT_PASS[$i]} + 1 ))
}

fail() {
  $QUIET || echo "  FAIL  $1"
  ERRORS=$((ERRORS + 1))
  local i=$(( ${#CAT_FAIL[@]} - 1 ))
  CAT_FAIL[$i]=$(( ${CAT_FAIL[$i]} + 1 ))
}

# Extract frontmatter value: frontmatter_val <file> <key>
# Returns the value or empty string; always exits 0
frontmatter_val() {
  local file="$1" key="$2"
  sed -n '2,/^---$/p' "$file" | grep -F "${key}:" | head -1 | sed -e "s/^${key}:[[:space:]]*//" -e 's/^["'"'"']//' -e 's/["'"'"']$//' || true
}

# ── Plugin Manifest ──────────────────────────────────────────────

begin_category "Manifest"

pjson="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
if [ -f "$pjson" ]; then
  if jq empty "$pjson" 2>/dev/null; then
    pass "plugin.json is valid JSON"
  else
    fail "plugin.json is not valid JSON"
  fi
  for field in name description version; do
    val=$(jq -r ".${field} // empty" "$pjson" 2>/dev/null || true)
    if [ -n "$val" ]; then
      pass "plugin.json has '${field}': ${val}"
    else
      fail "plugin.json missing '${field}'"
    fi
  done
  # Check semver
  ver=$(jq -r '.version // empty' "$pjson" 2>/dev/null || true)
  if echo "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "plugin.json version is valid semver"
  else
    fail "plugin.json version '${ver}' is not valid semver (expected X.Y.Z)"
  fi
else
  fail "plugin.json not found at ${pjson}"
fi

# ── Hooks ────────────────────────────────────────────────────────

begin_category "Hooks"

hjson="${PLUGIN_ROOT}/hooks/hooks.json"
if [ -f "$hjson" ]; then
  if jq empty "$hjson" 2>/dev/null; then
    pass "hooks.json is valid JSON"
  else
    fail "hooks.json is not valid JSON"
  fi
  # Check referenced scripts exist and are executable
  for script_ref in $(jq -r '.. | .command? // empty' "$hjson" 2>/dev/null | grep -oE "hooks/[a-z_-]+" | sort -u || true); do
    script_path="${PLUGIN_ROOT}/${script_ref}"
    script_name=$(basename "$script_ref")
    if [ -f "$script_path" ]; then
      pass "hook script '${script_name}' exists"
      if [ -x "$script_path" ]; then
        pass "hook script '${script_name}' is executable"
      else
        fail "hook script '${script_name}' is not executable"
      fi
    else
      fail "hook script '${script_name}' not found at ${script_path}"
    fi
  done
  # Check slop-patterns.json exists and is valid JSON
  slop_catalog="${PLUGIN_ROOT}/slop-patterns.json"
  if [ -f "$slop_catalog" ]; then
    if jq empty "$slop_catalog" 2>/dev/null; then
      pass "slop-patterns.json exists and is valid JSON"
    else
      fail "slop-patterns.json is not valid JSON"
    fi
  else
    fail "slop-patterns.json not found at ${slop_catalog}"
  fi
else
  fail "hooks.json not found at ${hjson}"
fi

# ── Skills ───────────────────────────────────────────────────────

begin_category "Skills"

skill_count=0
for skill_dir in "${PLUGIN_ROOT}"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  dir_name=$(basename "$skill_dir")
  skill_file="${skill_dir}SKILL.md"
  if [ ! -f "$skill_file" ]; then
    fail "skill '${dir_name}' missing SKILL.md"
    continue
  fi
  skill_count=$((skill_count + 1))
  # Check frontmatter delimiters
  first_line=$(head -1 "$skill_file")
  if [ "$first_line" != "---" ]; then
    fail "skill '${dir_name}' missing frontmatter (no opening ---)"
    continue
  fi
  # Check required fields
  name_val=$(frontmatter_val "$skill_file" "name")
  desc_val=$(frontmatter_val "$skill_file" "description")
  if [ -n "$name_val" ]; then
    if [ "$name_val" = "$dir_name" ]; then
      pass "skill '${dir_name}' name matches directory"
    else
      fail "skill '${dir_name}' name mismatch: frontmatter says '${name_val}'"
    fi
  else
    fail "skill '${dir_name}' missing 'name' in frontmatter"
  fi
  if [ -n "$desc_val" ]; then
    pass "skill '${dir_name}' has description"
  else
    fail "skill '${dir_name}' missing 'description' in frontmatter"
  fi
done
$QUIET || echo "  (${skill_count} skills found)"

# ── Agents ───────────────────────────────────────────────────────

begin_category "Agents"

valid_tools="Read|Write|Edit|Bash|Glob|Grep|NotebookRead|NotebookEdit|WebFetch|WebSearch|Agent|TodoWrite|AskUserQuestion|TaskCreate|TaskGet|TaskUpdate|TaskList|Skill|SendMessage|EnterPlanMode|ExitPlanMode|ToolSearch"
valid_models="opus|sonnet|haiku"
agent_count=0
for agent_file in "${PLUGIN_ROOT}"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_count=$((agent_count + 1))
  file_name=$(basename "$agent_file" .md)
  first_line=$(head -1 "$agent_file")
  if [ "$first_line" != "---" ]; then
    fail "agent '${file_name}' missing frontmatter"
    continue
  fi
  name_val=$(frontmatter_val "$agent_file" "name")
  desc_val=$(frontmatter_val "$agent_file" "description")
  tools_val=$(frontmatter_val "$agent_file" "tools")
  model_val=$(frontmatter_val "$agent_file" "model")

  if [ -n "$name_val" ] && [ "$name_val" = "$file_name" ]; then
    pass "agent '${file_name}' name matches filename"
  elif [ -n "$name_val" ]; then
    fail "agent '${file_name}' name mismatch: frontmatter says '${name_val}'"
  else
    fail "agent '${file_name}' missing 'name'"
  fi

  if [ -n "$desc_val" ]; then
    pass "agent '${file_name}' has description"
  else
    fail "agent '${file_name}' missing 'description'"
  fi

  if [ -n "$tools_val" ]; then
    # Check each tool is valid
    all_valid=true
    IFS=', ' read -ra tool_list <<< "$tools_val"
    for tool in "${tool_list[@]}"; do
      tool=$(echo "$tool" | xargs)  # trim whitespace
      if ! echo "$tool" | grep -qE "^(${valid_tools})$"; then
        fail "agent '${file_name}' has unknown tool '${tool}'"
        all_valid=false
      fi
    done
    if $all_valid; then
      pass "agent '${file_name}' tools are valid: ${tools_val}"
    fi
  else
    fail "agent '${file_name}' missing 'tools'"
  fi

  if [ -n "$model_val" ]; then
    if echo "$model_val" | grep -qE "^(${valid_models})$"; then
      pass "agent '${file_name}' model is valid: ${model_val}"
    else
      fail "agent '${file_name}' has unknown model '${model_val}'"
    fi
  else
    fail "agent '${file_name}' missing 'model'"
  fi

  valid_memory_scopes="user|project|local"
  memory_val=$(frontmatter_val "$agent_file" "memory")
  if [ -n "$memory_val" ]; then
    if echo "$memory_val" | grep -qE "^(${valid_memory_scopes})$"; then
      pass "agent '${file_name}' memory scope is valid: ${memory_val}"
    else
      fail "agent '${file_name}' has invalid memory scope '${memory_val}'"
    fi
  fi

  # color is optional, any non-empty string is valid (hex, CSS name, etc.)
  color_val=$(frontmatter_val "$agent_file" "color")
  if [ -n "$color_val" ]; then
    pass "agent '${file_name}' has color: ${color_val}"
  fi

  # skills is optional, comma-separated list of skill names
  skills_val=$(frontmatter_val "$agent_file" "skills")
  if [ -n "$skills_val" ]; then
    pass "agent '${file_name}' has skills: ${skills_val}"
  fi

  # disallowedTools is optional, must be valid tool names
  disallowed_val=$(frontmatter_val "$agent_file" "disallowedTools")
  if [ -n "$disallowed_val" ]; then
    all_valid=true
    IFS=', ' read -ra disallowed_list <<< "$disallowed_val"
    for tool in "${disallowed_list[@]}"; do
      tool=$(echo "$tool" | xargs)
      if ! echo "$tool" | grep -qE "^(${valid_tools})$"; then
        fail "agent '${file_name}' has unknown disallowed tool '${tool}'"
        all_valid=false
      fi
    done
    if $all_valid; then
      pass "agent '${file_name}' disallowedTools are valid: ${disallowed_val}"
    fi
  fi
done
$QUIET || echo "  (${agent_count} agents found)"

# ── Commands ─────────────────────────────────────────────────────

begin_category "Commands"

cmd_count=0
for cmd_file in "${PLUGIN_ROOT}"/commands/*.md; do
  [ -f "$cmd_file" ] || continue
  cmd_count=$((cmd_count + 1))
  cmd_name=$(basename "$cmd_file" .md)
  first_line=$(head -1 "$cmd_file")
  if [ "$first_line" != "---" ]; then
    fail "command '${cmd_name}' missing frontmatter"
    continue
  fi
  desc_val=$(frontmatter_val "$cmd_file" "description")
  if [ -n "$desc_val" ]; then
    pass "command '${cmd_name}' has description"
  else
    fail "command '${cmd_name}' missing 'description'"
  fi
  # Check argument-hint consistency: present iff command uses $ARGUMENTS
  hint_val=$(frontmatter_val "$cmd_file" "argument-hint" || true)
  uses_args=$(grep -c '\$ARGUMENTS' "$cmd_file" 2>/dev/null || true)
  if [ "$uses_args" -gt 0 ] && [ -z "$hint_val" ]; then
    fail "command '${cmd_name}' uses \$ARGUMENTS but missing 'argument-hint'"
  elif [ "$uses_args" -eq 0 ] && [ -n "$hint_val" ]; then
    fail "command '${cmd_name}' has 'argument-hint' but never uses \$ARGUMENTS"
  elif [ "$uses_args" -gt 0 ] && [ -n "$hint_val" ]; then
    pass "command '${cmd_name}' has argument-hint"
  fi
done
$QUIET || echo "  (${cmd_count} commands found)"

# ── Output Styles ────────────────────────────────────────────────

begin_category "Output Styles"

style_count=0
for style_file in "${PLUGIN_ROOT}"/output-styles/*.md; do
  [ -f "$style_file" ] || continue
  style_count=$((style_count + 1))
  style_name=$(basename "$style_file" .md)
  first_line=$(head -1 "$style_file")
  if [ "$first_line" != "---" ]; then
    fail "output-style '${style_name}' missing frontmatter"
    continue
  fi
  name_val=$(frontmatter_val "$style_file" "name")
  desc_val=$(frontmatter_val "$style_file" "description")
  if [ -n "$name_val" ]; then
    pass "output-style '${style_name}' has name: ${name_val}"
  else
    fail "output-style '${style_name}' missing 'name'"
  fi
  if [ -n "$desc_val" ]; then
    pass "output-style '${style_name}' has description"
  else
    fail "output-style '${style_name}' missing 'description'"
  fi
done
$QUIET || echo "  (${style_count} output styles found)"

# ── Lib Scripts ──────────────────────────────────────────────────

begin_category "Lib Scripts"

for lib_script in rnd-dir.sh bump.sh; do
  script_path="${PLUGIN_ROOT}/lib/${lib_script}"
  if [ -f "$script_path" ]; then
    pass "lib/${lib_script} exists"
    if [ -x "$script_path" ]; then
      pass "lib/${lib_script} is executable"
    else
      fail "lib/${lib_script} is not executable"
    fi
  else
    fail "lib/${lib_script} not found"
  fi
done

# ── Cross-References ─────────────────────────────────────────────

begin_category "Cross-References"

# Collect all valid skill names
valid_skills=""
for skill_dir in "${PLUGIN_ROOT}"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  valid_skills="${valid_skills} $(basename "$skill_dir")"
done

# Check skill references in using-rnd-framework table
xref_count=0
urfm="${PLUGIN_ROOT}/skills/using-rnd-framework/SKILL.md"
if [ -f "$urfm" ]; then
  # Match backtick-wrapped skill refs, exclude /command refs and agent refs
  while IFS= read -r ref; do
    ref_name="${ref#rnd-framework:}"  # strip plugin prefix
    xref_count=$((xref_count + 1))
    if echo "$valid_skills" | grep -qw "$ref_name"; then
      pass "using-rnd-framework skill ref '${ref}' resolves"
    else
      fail "using-rnd-framework skill ref '${ref}' — skill '${ref_name}' not found"
    fi
  done < <(grep -oE '`rnd-framework:[a-z-]+`' "$urfm" | tr -d '`' | sort -u)
fi

# Check skill references in agent "Required Skills" sections
for agent_file in "${PLUGIN_ROOT}"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  agent_name=$(basename "$agent_file" .md)
  while IFS= read -r ref; do
    ref_name="${ref#rnd-framework:}"
    xref_count=$((xref_count + 1))
    if echo "$valid_skills" | grep -qw "$ref_name"; then
      pass "agent '${agent_name}' skill ref '${ref}' resolves"
    else
      fail "agent '${agent_name}' skill ref '${ref}' — skill '${ref_name}' not found"
    fi
  done < <(grep -oE 'rnd-framework:[a-z-]+' "$agent_file" | sort -u)
done

# Check agent references in commands (spawn instructions)
valid_agents=""
for agent_file in "${PLUGIN_ROOT}"/agents/*.md; do
  [ -f "$agent_file" ] || continue
  valid_agents="${valid_agents} rnd-framework:$(basename "$agent_file" .md)"
done
# Build valid_skill_refs for cross-reference lookups (plugin-prefixed)
valid_skill_refs=""
for skill_dir in "${PLUGIN_ROOT}"/skills/*/; do
  [ -d "$skill_dir" ] || continue
  valid_skill_refs="${valid_skill_refs} rnd-framework:$(basename "$skill_dir")"
done
for cmd_file in "${PLUGIN_ROOT}"/commands/*.md; do
  [ -f "$cmd_file" ] || continue
  cmd_name=$(basename "$cmd_file" .md)
  while IFS= read -r ref; do
    xref_count=$((xref_count + 1))
    if echo "$valid_agents" | grep -qw "$ref"; then
      pass "command '${cmd_name}' agent ref '${ref}' resolves"
    elif echo "$valid_skill_refs" | grep -qw "$ref"; then
      pass "command '${cmd_name}' skill ref '${ref}' resolves"
    else
      fail "command '${cmd_name}' agent ref '${ref}' — agent not found"
    fi
  done < <(grep -oE 'rnd-framework:rnd-[a-z-]+' "$cmd_file" | sort -u)
done
$QUIET || echo "  (${xref_count} cross-references checked)"

# ── Content Parity ───────────────────────────────────────────────

begin_category "Content Parity"

# Data-driven parity table: "skill_path|agent_path|marker|description"
parity_table=(
  "skills/rnd-decomposition/SKILL.md|agents/rnd-planner.md|External dependencies|pre-registration field"
  "skills/rnd-building/SKILL.md|agents/rnd-builder.md|erify external dependencies|step 2.5"
  "skills/rnd-building/SKILL.md|agents/rnd-builder.md|Verified external assumptions|self-assessment sub-section"
  "skills/rnd-building/SKILL.md|agents/rnd-builder.md|Unverified external assumptions|self-assessment sub-section"
  "skills/rnd-verification/SKILL.md|agents/rnd-verifier.md|External contract conformance|failure mode analysis"
  "skills/rnd-verification/SKILL.md|agents/rnd-verifier.md|assumptions about external systems|code inspection"
  "skills/rnd-verification/SKILL.md|agents/rnd-verifier.md|ulti-Judge|multi-judge consensus protocol"
  "skills/rnd-decomposition/SKILL.md|agents/rnd-planner.md|ocal expert|local expert field parity"
  "skills/rnd-data-science/SKILL.md|agents/rnd-data-scientist.md|mcp__julia__julia_eval|Julia MCP tool reference"
  "skills/rnd-data-science/SKILL.md|agents/rnd-data-scientist.md|Validate input data|data validation requirement"
  "skills/rnd-data-science/SKILL.md|agents/rnd-data-scientist.md|independent cross-check|numerical verification approach"
  "skills/rnd-data-science/SKILL.md|agents/rnd-data-scientist.md|never hardcode|no intermediate value hardcoding rule"
  "skills/rnd-data-science/SKILL.md|agents/rnd-data-scientist.md|read_csv|DuckDB CSV function reference"
  "skills/rnd-data-science/SKILL.md|agents/rnd-data-scientist.md|duckdb -c|DuckDB CLI invocation pattern"
  "skills/rnd-data-science/SKILL.md|agents/rnd-data-scientist.md|Tool Selection|DuckDB vs Julia decision table"
  # T1: multi-judge file path parity
  "skills/rnd-multi-judge/SKILL.md|commands/verify.md|judge-a.md|multi-judge judge-a file naming"
  "skills/rnd-multi-judge/SKILL.md|commands/verify.md|judge-b.md|multi-judge judge-b file naming"
  "skills/rnd-multi-judge/SKILL.md|commands/verify.md|tiebreaker.md|multi-judge tiebreaker file naming"
  "skills/rnd-multi-judge/SKILL.md|commands/start.md|judge-a.md|multi-judge judge-a file naming in start"
  "skills/rnd-multi-judge/SKILL.md|commands/start.md|judge-b.md|multi-judge judge-b file naming in start"
  "skills/rnd-multi-judge/SKILL.md|commands/start.md|tiebreaker.md|multi-judge tiebreaker file naming in start"
  "skills/rnd-multi-judge/SKILL.md|commands/verify.md|Consensus method|multi-judge consensus method field"
  # T2: local expert discovery parity
  "skills/rnd-local-experts/SKILL.md|commands/start.md|.claude/agents/|local expert agents discovery path"
  "skills/rnd-local-experts/SKILL.md|commands/start.md|.claude/skills/|local expert skills discovery path"
  "skills/rnd-local-experts/SKILL.md|commands/start.md|Local Experts Discovered|local expert discovery summary field"
  # T3: local expert invocation parity
  "skills/rnd-local-experts/SKILL.md|agents/rnd-planner.md|Local Experts Discovered|local expert discovery field in planner"
  "skills/rnd-local-experts/SKILL.md|skills/rnd-decomposition/SKILL.md|ocal expert|local expert field in decomposition skill"
  # Feature 2: failure modes parity
  "skills/rnd-failure-modes/SKILL.md|agents/rnd-verifier.md|failure modes|failure modes catalog reference in verifier"
  "skills/rnd-failure-modes/SKILL.md|skills/rnd-verification/SKILL.md|failure modes|failure modes catalog reference in verification skill"
  # Feature 3: builder status codes parity
  "skills/rnd-building/SKILL.md|agents/rnd-builder.md|DONE_WITH_CONCERNS|builder status code DONE_WITH_CONCERNS parity"
  "skills/rnd-building/SKILL.md|agents/rnd-builder.md|NEEDS_CONTEXT|builder status code NEEDS_CONTEXT parity"
  # Feature 4: tiered criteria parity
  "skills/rnd-decomposition/SKILL.md|agents/rnd-planner.md|Correctness:|tiered criteria Correctness marker in planner"
  # T7: slop-gate parity checks
  "skills/rnd-slop-detection/SKILL.md|slop-patterns.json|over-commenting|slop skill and catalog share over-commenting category"
  "skills/rnd-slop-detection/SKILL.md|slop-patterns.json|error-handling|slop skill and catalog share error-handling category"
  "skills/rnd-slop-detection/SKILL.md|slop-patterns.json|hygiene|slop skill and catalog share hygiene category"
  "hooks/slop-gate|slop-patterns.json|severity|slop-gate hook and catalog share severity field schema"
  "skills/rnd-slop-detection/SKILL.md|hooks/slop-gate|PASS|slop skill and hook share PASS verdict"
  "skills/rnd-slop-detection/SKILL.md|hooks/slop-gate|WARN|slop skill and hook share WARN verdict"
  "skills/rnd-slop-detection/SKILL.md|hooks/slop-gate|FAIL|slop skill and hook share FAIL verdict"
)

for entry in "${parity_table[@]}"; do
  IFS='|' read -r skill_rel agent_rel marker desc <<< "$entry"
  skill_file="${PLUGIN_ROOT}/${skill_rel}"
  agent_file="${PLUGIN_ROOT}/${agent_rel}"
  skill_name=$(basename "$(dirname "$skill_rel")")
  agent_name=$(basename "$agent_rel" .md)
  skill_has=false
  agent_has=false
  grep -qi "$marker" "$skill_file" 2>/dev/null && skill_has=true
  grep -qi "$marker" "$agent_file" 2>/dev/null && agent_has=true
  if $skill_has && $agent_has; then
    pass "parity: '${marker}' in ${skill_name} and ${agent_name} (${desc})"
  elif $skill_has && ! $agent_has; then
    fail "parity: '${marker}' in ${skill_name} but missing in ${agent_name}"
  elif ! $skill_has && $agent_has; then
    fail "parity: '${marker}' in ${agent_name} but missing in ${skill_name}"
  else
    fail "parity: '${marker}' missing in both ${skill_name} and ${agent_name}"
  fi
done

# ── Summary Table ────────────────────────────────────────────────

echo ""
echo "=== Summary ==="
echo ""
printf "  %-20s %6s %6s   %s\n" "Category" "Pass" "Fail" "Status"
printf "  %-20s %6s %6s   %s\n" "────────────────────" "──────" "──────" "──────"
for i in "${!CAT_NAMES[@]}"; do
  p=${CAT_PASS[$i]}
  f=${CAT_FAIL[$i]}
  if [ "$f" -gt 0 ]; then
    status="FAIL"
  else
    status="ok"
  fi
  printf "  %-20s %6d %6d   %s\n" "${CAT_NAMES[$i]}" "$p" "$f" "$status"
done
printf "  %-20s %6s %6s\n" "────────────────────" "──────" "──────"
printf "  %-20s %6d %6d\n" "Total" "$PASSES" "$ERRORS"
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "  ${ERRORS} check(s) failed."
  exit 1
else
  echo "  All ${PASSES} checks passed."
  exit 0
fi
