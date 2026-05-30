#!/usr/bin/env bash
# lib/post-review-writer.sh — Per-finding ground-truth record writer.
#
# Appends ONE JSON line per finding to the slug-root post-review.jsonl
# (sibling to calibration.jsonl, resolved via rnd-dir.sh --calibration dirname).
#
# Grain: per-finding. Downstream consumers (the Section 8 SQL view and the
# validity ledger) collapse to per-(session,shape) before counting — a session
# with N findings is ONE dirty session, not N. Declare the grain here so
# consumers know what they are aggregating over.
#
# Shape attribution is purely mechanical (no reviewer judgment):
#   touched-file → owning task (grep path in the build manifests'
#   "## Files written" sections) → task's first assertion_shape in audit.jsonl.
#
# The owning task is resolved by the manifest filename's uuid, NOT a substring
# on the T<NN> slot. Manifests follow the canonical convention
# M<NN>-T<NN>-<uuid>-manifest.md; the <uuid> is matched EXACTLY against
# features.json .uuid, so M1.T01 and M2.T01 (which share the T01 slot) never
# cross-contaminate. A manifest filename that does NOT match the convention
# contributes NO attribution — it is skipped. Better an honest unattributable
# than a substring-guessed wrong shape: there is no legacy substring fallback.
#
# Co-owned files: when a touched file appears in MORE THAN ONE conforming
# manifest, the owning task is the one at the LATEST pipeline stage — highest
# milestone number, then highest task number (the <NN> integers parsed from the
# filename), tie-broken by lexicographically-largest uuid (an impossible tie,
# since uuids make filenames unique, but kept for total determinism). The choice
# is independent of glob order and features.json ordering — a co-owned finding
# attributes to the most-recent stage that touched the file, not whichever
# manifest the glob happened to enumerate first.
#
# verifier_said_PASS is DERIVED from the owning task's aggregated verdict in
# $session_dir/verifications/wave-*-verdict-map.json (keyed by assertion ID;
# each entry {verdict, evidence[], feedback, task_id}). Aggregating the entries
# whose task_id == owning_task: PASS iff none is FAIL or NEEDS_ITERATION. This
# keeps the verdict and the shape derived from the SAME owning task. The
# --verifier-said-pass flag is an OPTIONAL override used only as a FALLBACK when
# no verdict-map entry exists for the owning task (unattributable findings, or
# no verdict maps present). Clean-row mode is unaffected (it hardcodes true).
#
# Multi-shape tie-break: when a task has multiple distinct assertion shapes,
# the FIRST shape encountered in audit.jsonl for that task_id is used.
# audit.jsonl is append-only and the shape-producer writes shapes in assertion
# order, so this is stable and deterministic.
#
# Unattributable findings (file in no manifest): emitted with shape:"unattributable".
# No findings are ever dropped — FM4.
#
# Clean-row mode: --clean-shape <shape> records a clean (session, shape) row for
# an explicitly-given shape WITHOUT running file→task attribution and WITHOUT
# requiring --touched-file. The shape must be a member of the x-shape-vocab in
# event-schema.json. The emitted row carries review_found:false and the
# clean-distinct severity "none" (never the finding-severity "info", which would
# overload a real info-finding value). Downstream the Section 8 view keys
# dirtiness off review_found, not severity, so "none" is safe.
#
# Usage:
#   post-review-writer.sh \
#     --session-dir    <path>       Session dir (contains builds/, features.json, audit.jsonl)
#     --session-id     <id>         Session ID (e.g. 20260530-082054-a3fc285c)
#     --touched-file   <path>       Repo-relative path of the reviewed file
#     --severity       <level>      critical|major|minor|info
#     --verifier-said-pass <bool>   true|false — did the in-pipeline verifier pass the owning task?
#     --review-found   <bool>       true|false — is this an actual finding (always true for a finding row)
#
#   post-review-writer.sh \
#     --session-id     <id>         Session ID
#     --clean-shape    <shape>      A member of x-shape-vocab — emits one clean row, no attribution
#
# Environment:
#   CLAUDE_PLUGIN_DATA   Preferred slug root (post-review.jsonl sibling of calibration.jsonl).
#                        Falls back to rnd-dir.sh --calibration dirname.
#   CLAUDE_PLUGIN_ROOT   Required for rnd-dir.sh fallback path resolution.

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

session_dir=""
session_id=""
touched_file=""
severity=""
verifier_said_pass=""
review_found=""
clean_shape=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session-dir)        session_dir="$2";        shift 2 ;;
    --session-id)         session_id="$2";         shift 2 ;;
    --touched-file)       touched_file="$2";       shift 2 ;;
    --severity)           severity="$2";           shift 2 ;;
    --verifier-said-pass) verifier_said_pass="$2"; shift 2 ;;
    --review-found)       review_found="$2";       shift 2 ;;
    --clean-shape)        clean_shape="$2";        shift 2 ;;
    *) printf 'post-review-writer.sh: unknown argument: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[[ -n "$session_id" ]] || { printf 'post-review-writer.sh: --session-id required\n' >&2; exit 1; }

# ---------------------------------------------------------------------------
# Resolve output path: slug-root post-review.jsonl
# ---------------------------------------------------------------------------

_post_review_file() {
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    printf '%s/post-review.jsonl' "$CLAUDE_PLUGIN_DATA"
  else
    local calib_path
    calib_path="$("${_SCRIPT_DIR}/rnd-dir.sh" --calibration)"
    printf '%s/post-review.jsonl' "$(dirname "$calib_path")"
  fi
}

_emit_record() {
  # $1 shape  $2 severity  $3 verifier_said_PASS(json)  $4 review_found(json)
  local out_file
  out_file="$(_post_review_file)"

  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  jq -nc \
    --arg shape             "$1" \
    --arg severity          "$2" \
    --argjson verifier_pass "$3" \
    --argjson review_found  "$4" \
    --arg session_id        "$session_id" \
    --arg timestamp         "$ts" \
    '{
      shape:             $shape,
      severity:          $severity,
      verifier_said_PASS: $verifier_pass,
      review_found:      $review_found,
      session_id:        $session_id,
      timestamp:         $timestamp
    }' >> "$out_file"
}

# ---------------------------------------------------------------------------
# Clean-row mode: --clean-shape <shape>
#
# Records ONE clean (session, shape) row for an explicitly-given shape with no
# file→task attribution. The shape must be a member of x-shape-vocab. Clean
# rows carry review_found:false and the clean-distinct severity "none".
# ---------------------------------------------------------------------------

if [[ -n "$clean_shape" ]]; then
  schema_file="${_SCRIPT_DIR}/event-schema.json"
  [[ -f "$schema_file" ]] || { printf 'post-review-writer.sh: event-schema.json not found at %s\n' "$schema_file" >&2; exit 1; }

  is_valid_shape="$(jq -r --arg s "$clean_shape" '
    (."x-shape-vocab" // []) | index($s) != null
  ' "$schema_file" 2>/dev/null || true)"

  [[ "$is_valid_shape" == "true" ]] || {
    printf 'post-review-writer.sh: --clean-shape %q is not in x-shape-vocab\n' "$clean_shape" >&2
    exit 1
  }

  _emit_record "$clean_shape" "none" "true" "false"
  exit 0
fi

# ---------------------------------------------------------------------------
# Finding mode: file→task attribution
# ---------------------------------------------------------------------------

[[ -n "$session_dir" ]]       || { printf 'post-review-writer.sh: --session-dir required\n' >&2; exit 1; }
[[ -n "$touched_file" ]]      || { printf 'post-review-writer.sh: --touched-file required\n' >&2; exit 1; }
[[ -n "$severity" ]]          || { printf 'post-review-writer.sh: --severity required\n' >&2; exit 1; }
[[ -n "$review_found" ]]      || { printf 'post-review-writer.sh: --review-found required\n' >&2; exit 1; }

# --verifier-said-pass is OPTIONAL: it is now a FALLBACK, used only when the
# owning task has no verdict-map entry to derive from. Default false.

# ---------------------------------------------------------------------------
# Attribution: touched-file → owning task → first shape in audit.jsonl
# ---------------------------------------------------------------------------

builds_dir="${session_dir}/builds"
features_file="${session_dir}/features.json"
audit_file="${session_dir}/audit.jsonl"

shape="unattributable"

# Does a manifest's ## Files written section list the touched file?
# Reads the block between "## Files written" and the next "## " heading and
# component-aligned-matches each entry against touched_file. Returns 0 on match.
_manifest_lists_touched() {
  local manifest="$1"

  local norm_touched="${touched_file#./}"; norm_touched="${norm_touched#/}"

  local in_section=0 line trimmed norm_entry
  while IFS= read -r line; do
    if [[ "$line" == "## Files written" ]]; then
      in_section=1
      continue
    fi

    if [[ $in_section -eq 1 ]]; then
      [[ "$line" == "##"* ]] && break

      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

      norm_entry="${trimmed#./}"; norm_entry="${norm_entry#/}"

      # Match exact OR component-aligned suffix, so an absolute or
      # differently-rooted touched file still matches the repo-relative form
      # manifests list. The "*/" prefix keeps the match component-aligned (so
      # "ab.sh" never matches "cab.sh").
      if [[ "$norm_entry" == "$norm_touched" \
         || "$norm_entry" == */"$norm_touched" \
         || "$norm_touched" == */"$norm_entry" ]]; then
        return 0
      fi
    fi
  done < "$manifest"

  return 1
}

if [[ -d "$builds_dir" ]] && [[ -f "$features_file" ]] && [[ -f "$audit_file" ]]; then
  # Find the owning task: among ALL conforming manifests whose ## Files written
  # lists touched_file, pick the one at the LATEST pipeline stage (highest
  # milestone, then highest task, then lexicographically-largest uuid). This is
  # deterministic and independent of glob order and features.json ordering —
  # a co-owned file attributes to the most-recent stage that touched it.
  owning_task=""
  best_milestone=-1
  best_task=-1
  best_uuid=""

  for manifest in "${builds_dir}"/*-manifest.md; do
    [[ -f "$manifest" ]] || continue

    # Only conforming names (M<NN>-T<NN>-<uuid>-manifest.md) carry an exact
    # uuid join key. Non-conforming filenames contribute no attribution.
    manifest_base="$(basename "$manifest")"
    manifest_key="${manifest_base%-manifest.md}"

    [[ "$manifest_key" =~ ^M([0-9]+)-T([0-9]+)-(.+)$ ]] || continue
    m_num=$((10#${BASH_REMATCH[1]}))
    t_num=$((10#${BASH_REMATCH[2]}))
    manifest_uuid="${BASH_REMATCH[3]}"

    _manifest_lists_touched "$manifest" || continue

    # Keep this manifest only if it is at a strictly later stage than the best
    # seen so far. Order: milestone, then task, then uuid (the uuid tie-break is
    # unreachable since uuids are unique, but kept for total determinism).
    if (( m_num > best_milestone )) \
       || { (( m_num == best_milestone )) && (( t_num > best_task )); } \
       || { (( m_num == best_milestone )) && (( t_num == best_task )) && [[ "$manifest_uuid" > "$best_uuid" ]]; }; then
      best_milestone=$m_num
      best_task=$t_num
      best_uuid="$manifest_uuid"
    fi
  done

  if [[ -n "$best_uuid" ]]; then
    # Resolve the owning task from the winning manifest's uuid. Match EXACTLY
    # against features.json .uuid — never a substring on T<NN>, which repeats
    # across milestones (M1.T01 and M2.T01 collide).
    owning_task="$(jq -r --arg u "$best_uuid" '
      .tasks[]
      | select(.uuid == $u)
      | .id
    ' "$features_file" 2>/dev/null || true)"
  fi

  if [[ -n "$owning_task" ]]; then
    # Resolve first assertion_shape for this task in audit.jsonl
    shape="$(jq -r --arg tid "$owning_task" '
      select(.event == "assertion_shape" and .task_id == $tid) | .shape
    ' "$audit_file" 2>/dev/null | head -1 || true)"

    # Fallback: no shape event found — treat as unattributable
    [[ -n "$shape" ]] || shape="unattributable"
  fi
fi

# ---------------------------------------------------------------------------
# Derive verifier_said_PASS from the owning task's aggregated verdict
#
# The verdict maps ($session_dir/verifications/wave-*-verdict-map.json) are
# keyed by assertion ID; each entry is {verdict, evidence[], feedback, task_id}.
# Aggregate the entries whose task_id == owning_task: PASS iff NONE of them is
# FAIL or NEEDS_ITERATION. This derives the verdict from the SAME owning task
# that produced the shape, closing the prior caller↔writer coupling.
#
# The --verifier-said-pass flag is the FALLBACK, used only when no verdict-map
# entry exists for the owning task (unattributable findings, or no maps present).
# For an attributed finding with a verdict-map entry, the DERIVED value wins.
# ---------------------------------------------------------------------------

# Normalize boolean strings to JSON booleans
_to_bool() {
  case "${1,,}" in
    true|1|yes) printf 'true' ;;
    *)          printf 'false' ;;
  esac
}

verifier_pass_json="$(_to_bool "$verifier_said_pass")"

if [[ -n "${owning_task:-}" ]]; then
  verdict_glob=("${session_dir}"/verifications/wave-*-verdict-map.json)

  # `count` is the number of entries for this task across all maps; `bad` the
  # number that are FAIL or NEEDS_ITERATION. Derive PASS iff count>0 and bad==0.
  task_count=0
  task_bad=0

  for vmap in "${verdict_glob[@]}"; do
    [[ -f "$vmap" ]] || continue

    counts="$(jq -r --arg tid "$owning_task" '
      [ .[] | select(.task_id == $tid) ] as $entries
      | "\($entries | length) \($entries | map(select(.verdict == "FAIL" or .verdict == "NEEDS_ITERATION")) | length)"
    ' "$vmap" 2>/dev/null || true)"

    [[ -n "$counts" ]] || continue

    read -r c b <<< "$counts"
    task_count=$(( task_count + c ))
    task_bad=$(( task_bad + b ))
  done

  if (( task_count > 0 )); then
    if (( task_bad == 0 )); then
      verifier_pass_json="true"
    else
      verifier_pass_json="false"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Emit record
# ---------------------------------------------------------------------------

_emit_record \
  "$shape" \
  "$severity" \
  "$verifier_pass_json" \
  "$(_to_bool "$review_found")"
