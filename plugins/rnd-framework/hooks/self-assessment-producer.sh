#!/usr/bin/env bash
# hooks/self-assessment-producer.sh — PostToolUse Write|Edit hook.
# Path-driven builder_self_assessment emitter.
#
# Fires when an agent writes a .../sessions/<id>/builds/<task>-self-assessment.md
# file. Derives session_id and task_id from the file path (never from
# active_session_dir or .current-session), reads the builder's explicit
# build_status from the file, and appends one builder_self_assessment record to
# the session audit.jsonl co-located with the builds/ directory.
#
# The record carries the RAW 4-valued build_status (DONE | DONE_WITH_CONCERNS |
# NEEDS_CONTEXT | BLOCKED). The pass/fail collapse is deliberately deferred to
# the consumer (lib/stats/self_fail_vs_verdict_gap.sql): a pass-with-caveats
# (DONE_WITH_CONCERNS) and a true block (BLOCKED) are distinct facts, and only
# the consumer should decide which count as a failure. The prior implementation
# inferred PASS/FAIL from markdown *shape* — which could not distinguish
# DONE_WITH_CONCERNS from BLOCKED (they emit the identical full template) and so
# mislabelled every full-template self-assessment FAIL.
#
# Non-blocking: always exits 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Read the builder's explicit build-status declaration from the self-assessment
# file body. The builder writes a `**Status:** <CODE>` line (see
# skills/rnd-building); <CODE> is one of the four status codes. We return the RAW
# code — the consumer collapses it to pass/fail.
#
# Status is structural, not inferable from layout: DONE_WITH_CONCERNS,
# NEEDS_CONTEXT, and BLOCKED all emit the identical full template, so no
# markdown-shape test can separate a caveat from a block. Only an explicit token
# carries the distinction.
#
# Order matters: DONE_WITH_CONCERNS must be tested before DONE (it contains the
# substring "DONE"). Fallback (no status line — legacy or forgotten): DONE. An
# unlabelled file is treated as a clean pass; shape alone no longer implies a
# status.
infer_build_status() {
  local content="$1" line

  line="$(printf '%s\n' "$content" \
    | grep -iE '^[[:space:]]*[*]*status[*]*[[:space:]]*:' \
    | head -n1 \
    | tr '[:lower:]' '[:upper:]')"

  case "$line" in
    *BLOCKED*)            printf 'BLOCKED' ;;
    *NEEDS_CONTEXT*)      printf 'NEEDS_CONTEXT' ;;
    *DONE_WITH_CONCERNS*) printf 'DONE_WITH_CONCERNS' ;;
    *DONE*)              printf 'DONE' ;;
    *)                   printf 'DONE' ;;
  esac
}

# Resolve a self-assessment filename stem to the canonical features.json task id
# (M<N>.T<NN>.<slug>) so the emitted task_id JOINs calibration and the verdict
# map. Resolution is keyed on the M<N>.T<NN> structural prefix — the only part of
# the id that is unique within a plan and immune to slug truncation (id-gen caps
# slugs at 32 chars), slug drift, and a null/absent uuid. Order:
#   1. exact id match → use it (the normal path; slug intact);
#   2. unique M<N>.T<NN> prefix match → use that task's id (self-heals a drifted
#      or truncated slug);
#   3. raw stem fallback → no features.json, a bare milestone-less slot, an
#      ambiguous prefix, or no match: never blocks, never invents a wrong id.
resolve_canonical_task_id() {
  local stem="$1" feats="$2"

  [[ -f "$feats" ]] || { printf '%s' "$stem"; return; }

  local resolved
  resolved="$(jq -r --arg stem "$stem" '
    (.tasks // []) as $t
    | ($t | map(.id)) as $ids
    | if ($ids | index($stem)) then $stem
      elif ($stem | test("^M[0-9]+[.]T[0-9]+")) then
        ($stem | capture("^(?<mt>M[0-9]+[.]T[0-9]+)").mt) as $mt
        | ([ $ids[] | select(startswith($mt + ".")) ]) as $m
        | (if ($m | length) == 1 then $m[0] else "" end)
      else "" end
  ' "$feats" 2>/dev/null || true)"

  if [[ -n "$resolved" && "$resolved" != "null" ]]; then
    printf '%s' "$resolved"
  else
    printf '%s' "$stem"
  fi
}

{
  raw="$(cat)"

  tool_name="$(printf '%s' "$raw" | jq -r '.tool_name // ""' 2>/dev/null || true)"

  case "$tool_name" in
    Write|Edit) ;;
    *) exit 0 ;;
  esac

  file_path="$(printf '%s' "$raw" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)"

  # Match: path must contain /sessions/ and end with -self-assessment.md
  # under a builds/ directory.
  case "$file_path" in
    */sessions/*/builds/*-self-assessment.md) ;;
    *) exit 0 ;;
  esac

  # Normalize to absolute if possible (handles relative path forms — FM1).
  abs_path="$(normalize_artifact_path "$file_path")"

  # Derive session_id from the (possibly normalized) path; fall back to raw.
  session_id="$(session_id_from_path "$abs_path")"

  if [[ -z "$session_id" ]]; then
    session_id="$(session_id_from_path "$file_path")"
  fi

  if [[ -z "$session_id" ]]; then
    exit 0
  fi

  # Compute the session dir (parent of builds/).
  builds_dir="${abs_path%/*}"
  session_dir="${builds_dir%/*}"

  audit_path="${session_dir}/audit.jsonl"

  # Derive the filename stem, then resolve it to the canonical features.json id
  # so the emitted task_id JOINs calibration and the verdict map.
  filename="${abs_path##*/}"
  raw_stem="${filename%-self-assessment.md}"
  task_id="$(resolve_canonical_task_id "$raw_stem" "${session_dir}/features.json")"

  # Read the file to extract the explicit build_status.
  assessment_content=""
  if [[ -f "$abs_path" ]]; then
    assessment_content="$(< "$abs_path")"
  fi

  # Emit the RAW build status; the stats consumer collapses it to pass/fail.
  build_status="$(infer_build_status "$assessment_content")"

  ts="$(iso_timestamp)"

  jq -nc \
    --arg event "builder_self_assessment" \
    --arg session_id "$session_id" \
    --arg task_id "$task_id" \
    --arg build_status "$build_status" \
    --arg ts "$ts" \
    '{event:$event, session_id:$session_id, task_id:$task_id, build_status:$build_status, timestamp:$ts}' \
    >> "$audit_path" 2>/dev/null || true

} || true

exit 0
