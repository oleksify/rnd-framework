#!/usr/bin/env bash
# tests/outside-view-wiring.test.sh — Content and ordering tests for the
# outside-view injection pre-step wired into Phase 1 of commands/rnd-start.md.
# Usage: bash tests/outside-view-wiring.test.sh
# Exits 0 if all tests pass, 1 if any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

RND_START="${PLUGIN_ROOT}/commands/rnd-start.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Return the first line number matching a literal pattern (empty if none).
first_line() {
  grep -n "$1" "$2" | head -1 | cut -d: -f1
}

# Return the count of exact matches of a literal string.
count_exact() {
  grep -c "$1" "$2" || true
}

# ---------------------------------------------------------------------------
# M4.wiring.outside-view-section-exists
# The heading appears exactly once.
# ---------------------------------------------------------------------------

printf '\n--- outside-view-section-exists ---\n'

heading_count="$(count_exact '^### Phase 1 pre-step: Outside-view injection$' "$RND_START")"

assert_eq \
  "outside-view injection heading appears exactly once" \
  "1" \
  "$heading_count"

# ---------------------------------------------------------------------------
# M4.wiring.ordering-after-premortem-before-planner
# Premortem heading line < outside-view heading line < planner Agent({ line.
# ---------------------------------------------------------------------------

printf '\n--- ordering-after-premortem-before-planner ---\n'

premortem_line="$(first_line '^### Phase 1 pre-step: Premortem fan-out$' "$RND_START")"
outside_view_line="$(first_line '^### Phase 1 pre-step: Outside-view injection$' "$RND_START")"

# The planner Agent({ is the one whose next few lines contain rnd-planner.
# Find the Agent({ line that precedes the rnd-planner subagent_type declaration.
planner_agent_block="$(grep -n 'subagent_type.*rnd-framework:rnd-planner' "$RND_START" | head -1)"
planner_subagent_line="$(printf '%s' "$planner_agent_block" | cut -d: -f1)"
# Walk backward from rnd-planner subagent_type line to find the Agent({ opener.
planner_spawn_line="$(awk -v target="$planner_subagent_line" '
  NR <= target && /Agent\(\{/ { last = NR }
  NR == target { print last; exit }
' "$RND_START")"

assert_eq \
  "premortem heading line found" \
  "pass" \
  "$([ -n "$premortem_line" ] && printf pass || printf fail)"

assert_eq \
  "outside-view heading line found" \
  "pass" \
  "$([ -n "$outside_view_line" ] && printf pass || printf fail)"

assert_eq \
  "planner spawn Agent({ line found" \
  "pass" \
  "$([ -n "$planner_spawn_line" ] && printf pass || printf fail)"

assert_eq \
  "premortem heading precedes outside-view heading" \
  "pass" \
  "$([ "${premortem_line:-0}" -lt "${outside_view_line:-0}" ] && printf pass || printf fail)"

assert_eq \
  "outside-view heading precedes planner spawn" \
  "pass" \
  "$([ "${outside_view_line:-0}" -lt "${planner_spawn_line:-0}" ] && printf pass || printf fail)"

# ---------------------------------------------------------------------------
# M4.wiring.planner-prompt-includes-block
# The Planner spawn block contains ${OUTSIDE_VIEW_BLOCK} or cat .*outside-view.
# ---------------------------------------------------------------------------

printf '\n--- planner-prompt-includes-block ---\n'

# Extract lines from planner spawn Agent({ to its closing }).
spawn_start="$planner_spawn_line"
spawn_end="$(awk -v start="$spawn_start" '
  NR > start && /^\}\)/ { print NR; exit }
' "$RND_START")"

planner_block="$(awk -v s="$spawn_start" -v e="$spawn_end" 'NR>=s && NR<=e' "$RND_START")"

block_ref_count="$(printf '%s' "$planner_block" | grep -cE '\$\{OUTSIDE_VIEW_BLOCK\}|cat[^"]*outside-view' || true)"

assert_eq \
  "planner spawn prompt references OUTSIDE_VIEW_BLOCK or cat outside-view exactly once" \
  "1" \
  "$block_ref_count"

# ---------------------------------------------------------------------------
# M4.wiring.invokes-injector-and-emitter
# The outside-view section contains lib/outside-view.sh and lib/outside-view-emit.sh,
# emitter appearing after injector.
# ---------------------------------------------------------------------------

printf '\n--- invokes-injector-and-emitter ---\n'

# Extract the section: from the outside-view heading to the next ### heading.
section_start="$outside_view_line"
next_section_line="$(awk -v start="$section_start" '
  NR > start && /^### / { print NR; exit }
' "$RND_START")"

section_text="$(awk -v s="$section_start" -v e="${next_section_line:-9999}" \
  'NR>=s && NR<e' "$RND_START")"

injector_line_in_section="$(printf '%s' "$section_text" | grep -n 'lib/outside-view\.sh' | head -1 | cut -d: -f1)"
emitter_line_in_section="$(printf '%s' "$section_text" | grep -n 'lib/outside-view-emit\.sh' | head -1 | cut -d: -f1)"

assert_eq \
  "section contains lib/outside-view.sh reference" \
  "pass" \
  "$([ -n "$injector_line_in_section" ] && printf pass || printf fail)"

assert_eq \
  "section contains lib/outside-view-emit.sh reference" \
  "pass" \
  "$([ -n "$emitter_line_in_section" ] && printf pass || printf fail)"

assert_eq \
  "lib/outside-view-emit.sh appears after lib/outside-view.sh in section" \
  "pass" \
  "$([ "${injector_line_in_section:-0}" -lt "${emitter_line_in_section:-0}" ] && printf pass || printf fail)"

# ---------------------------------------------------------------------------
# M4.changelog.entry-exists-with-version-bump
# CHANGELOG contains a ## 5.5.0 — entry (anywhere in the file — later releases
# push it down but it must still exist), and the M4-scoped section contains a
# ### headline naming "outside-view" and "Planner" together.
# ---------------------------------------------------------------------------

printf '\n--- changelog-entry-exists-with-version-bump ---\n'

PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
CHANGELOG="${PLUGIN_ROOT}/CHANGELOG.md"

plugin_version="$(jq -r .version "$PLUGIN_JSON" 2>/dev/null || printf '')"

assert_eq \
  "plugin.json version is parseable" \
  "pass" \
  "$(printf '%s' "$plugin_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && printf pass || printf fail)"

changelog_header_count="$(grep -cE '^## 5\.5\.0 — ' "$CHANGELOG" || true)"

assert_eq \
  "CHANGELOG contains a ## 5.5.0 — entry" \
  "1" \
  "$changelog_header_count"

# Extract the M4-scoped section (lines between ## 5.5.0 and the next ## N.N.N).
m4_section="$(awk '/^## 5\.5\.0/{found=1; next} found && /^## [0-9]+\.[0-9]/{exit} found{print}' "$CHANGELOG" || true)"
headline_count="$(printf '%s' "$m4_section" | grep -cE '^### .*[Oo]utside.?[Vv]iew.*[Pp]lanner|^### .*[Pp]lanner.*[Oo]utside.?[Vv]iew' || true)"

assert_eq \
  "M4 section headline names outside-view and Planner together" \
  "1" \
  "$headline_count"

# ---------------------------------------------------------------------------
# M4.changelog.entry-content-matches-protocol
# The top entry body contains the four mandatory phrases, each of which also
# appears in tests/fixtures/protocol.md (the SSOT fixture).
# ---------------------------------------------------------------------------

printf '\n--- changelog-entry-content-matches-protocol ---\n'

PROTOCOL_FIXTURE="${SCRIPT_DIR}/fixtures/protocol.md"

# Extract text of top CHANGELOG entry: lines strictly between ## 5.5.0 and the next ## N.N.N entry.
top_entry="$(awk '/^## 5\.5\.0/{found=1; next} found && /^## [0-9]+\.[0-9]/{exit} found{print}' "$CHANGELOG" || true)"

# (a) thin-corpus threshold — n_total < 5 or n < 5
assert_eq \
  "CHANGELOG entry mentions n_total < 5 threshold" \
  "pass" \
  "$(printf '%s' "$top_entry" | grep -q 'n_total < 5\|n < 5' && printf pass || printf fail)"

assert_eq \
  "protocol.md contains n_total < 5 threshold" \
  "pass" \
  "$(grep -q 'n_total < 5\|n < 5' "$PROTOCOL_FIXTURE" && printf pass || printf fail)"

# (b) framing constraint — calibration anchor AND (not a license OR not license)
assert_eq \
  "CHANGELOG entry mentions calibration anchor" \
  "pass" \
  "$(printf '%s' "$top_entry" | grep -qi 'calibration anchor' && printf pass || printf fail)"

assert_eq \
  "CHANGELOG entry mentions not a license" \
  "pass" \
  "$(printf '%s' "$top_entry" | grep -qi 'not a license\|not license' && printf pass || printf fail)"

assert_eq \
  "protocol.md mentions calibration anchor" \
  "pass" \
  "$(grep -qi 'calibration anchor' "$PROTOCOL_FIXTURE" && printf pass || printf fail)"

# (c) audit event name
assert_eq \
  "CHANGELOG entry mentions outside_view_injected event" \
  "pass" \
  "$(printf '%s' "$top_entry" | grep -q 'outside_view_injected' && printf pass || printf fail)"

assert_eq \
  "protocol.md mentions outside_view_injected event" \
  "pass" \
  "$(grep -q 'outside_view_injected' "$PROTOCOL_FIXTURE" && printf pass || printf fail)"

# (d) wiring location — Phase 1 or rnd-start.md
assert_eq \
  "CHANGELOG entry mentions Phase 1 or rnd-start.md" \
  "pass" \
  "$(printf '%s' "$top_entry" | grep -q 'Phase 1\|rnd-start\.md' && printf pass || printf fail)"

assert_eq \
  "protocol.md mentions Phase 1 or rnd-start.md" \
  "pass" \
  "$(grep -q 'Phase 1\|rnd-start\.md' "$PROTOCOL_FIXTURE" && printf pass || printf fail)"

# ---------------------------------------------------------------------------
# M4.e2e.validate-sh-and-xrefs-clean
# Both validators exit 0 after the ship.
# ---------------------------------------------------------------------------

printf '\n--- validate-sh-and-xrefs-clean ---\n'

validate_exit=0
bash "${PLUGIN_ROOT}/lib/validate.sh" > /dev/null 2>&1 || validate_exit=$?

assert_eq \
  "lib/validate.sh exits 0" \
  "0" \
  "$validate_exit"

xrefs_exit=0
bash "${PLUGIN_ROOT}/lib/validate-xrefs.sh" > /dev/null 2>&1 || xrefs_exit=$?

assert_eq \
  "lib/validate-xrefs.sh exits 0" \
  "0" \
  "$xrefs_exit"

# ---------------------------------------------------------------------------
# M4.e2e.full-pipeline-emits-event
# Run the Phase 1 outside-view pre-step scripts with a sandboxed RND_DIR and
# confirm audit.jsonl gets the outside_view_injected event and outside-view.md
# is written and non-empty.
# ---------------------------------------------------------------------------

printf '\n--- full-pipeline-emits-event ---\n'

SANDBOX_DIR="$(mktemp -d)"
trap 'rm -rf "$SANDBOX_DIR"' EXIT

export RND_DIR="$SANDBOX_DIR"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# Run the injector (mirrors the Phase 1 bash block in commands/rnd-start.md).
injector_exit=0
OUTSIDE_VIEW_BLOCK="$("${PLUGIN_ROOT}/lib/outside-view.sh" 2>/dev/null)" || injector_exit=$?

assert_eq \
  "injector exits 0" \
  "0" \
  "$injector_exit"

assert_eq \
  "outside-view.md is written and non-empty" \
  "pass" \
  "$([ -s "$SANDBOX_DIR/outside-view.md" ] && printf pass || printf fail)"

# Run the emitter (mirrors the Phase 1 emitter bash block).
_ov_mode="$(grep -m1 '^- Mode:' "$SANDBOX_DIR/outside-view.md" | sed 's/^- Mode: //' || printf 'unavailable')"
_ov_n_total="$(grep -m1 '^- n_total:' "$SANDBOX_DIR/outside-view.md" | sed 's/^- n_total: //' || printf '0')"
_ov_shapes="$({ grep '^- Shape:' "$SANDBOX_DIR/outside-view.md" || true; } | \
  awk '{
    for (i=1;i<=NF;i++) {
      if ($i~/^Shape:/) shape=substr($i,7)
      if ($i~/^task_count=/) tc=substr($i,12)
      if ($i~/^fail_count=/) fc=substr($i,12)
      if ($i~/^fail_rate=/) fr=substr($i,11)
    }
    printf "{\"shape\":\"%s\",\"task_count\":%s,\"fail_count\":%s,\"fail_rate\":%s}\n", shape,tc,fc,fr
  }' | jq -sc '.' 2>/dev/null)"
[[ -n "$_ov_shapes" ]] || _ov_shapes='[]'
_ov_framing="$(grep -q '^## Framing constraint' "$SANDBOX_DIR/outside-view.md" && printf true || printf false)"

emitter_exit=0
"${PLUGIN_ROOT}/lib/outside-view-emit.sh" \
  "${_ov_mode:-unavailable}" \
  "${_ov_n_total:-0}" \
  "${_ov_shapes:-[]}" \
  "${_ov_framing:-false}" || emitter_exit=$?

assert_eq \
  "emitter exits 0" \
  "0" \
  "$emitter_exit"

assert_eq \
  "audit.jsonl exists after emitter" \
  "pass" \
  "$([ -f "$SANDBOX_DIR/audit.jsonl" ] && printf pass || printf fail)"

event_count="$(jq -r 'select(.event == "outside_view_injected")' "$SANDBOX_DIR/audit.jsonl" 2>/dev/null | grep -c '"event"' || true)"

assert_eq \
  "audit.jsonl contains exactly one outside_view_injected event" \
  "1" \
  "$event_count"

event_parseable="$(jq -e 'select(.event == "outside_view_injected") | .mode' "$SANDBOX_DIR/audit.jsonl" 2>/dev/null | grep -c '.' || true)"

assert_eq \
  "outside_view_injected event is parseable with .mode field" \
  "1" \
  "$event_parseable"

# ---------------------------------------------------------------------------
report
