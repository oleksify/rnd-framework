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
[[ -n "$verifier_said_pass" ]] || { printf 'post-review-writer.sh: --verifier-said-pass required\n' >&2; exit 1; }
[[ -n "$review_found" ]]      || { printf 'post-review-writer.sh: --review-found required\n' >&2; exit 1; }

# ---------------------------------------------------------------------------
# Attribution: touched-file → owning task → first shape in audit.jsonl
# ---------------------------------------------------------------------------

builds_dir="${session_dir}/builds"
features_file="${session_dir}/features.json"
audit_file="${session_dir}/audit.jsonl"

shape="unattributable"

if [[ -d "$builds_dir" ]] && [[ -f "$features_file" ]] && [[ -f "$audit_file" ]]; then
  # Find the owning task: scan each conforming manifest's ## Files written
  # section for touched_file, then resolve via the manifest's exact uuid.
  owning_task=""

  for manifest in "${builds_dir}"/*-manifest.md; do
    [[ -f "$manifest" ]] || continue

    # Only conforming names (M<NN>-T<NN>-<uuid>-manifest.md) carry an exact
    # uuid join key. Non-conforming filenames contribute no attribution.
    manifest_base="$(basename "$manifest")"
    manifest_key="${manifest_base%-manifest.md}"

    manifest_uuid=""
    if [[ "$manifest_key" =~ ^M[0-9]+-T[0-9]+-(.+)$ ]]; then
      manifest_uuid="${BASH_REMATCH[1]}"
    fi

    [[ -n "$manifest_uuid" ]] || continue

    # Extract the ## Files written block: lines after the heading up to the
    # next ## heading or end-of-file. Check if touched_file appears there.
    in_section=0
    while IFS= read -r line; do
      if [[ "$line" == "## Files written" ]]; then
        in_section=1
        continue
      fi

      if [[ $in_section -eq 1 ]]; then
        if [[ "$line" == "##"* ]]; then
          break
        fi

        # Strip leading/trailing whitespace for comparison
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

        # Normalize both sides (strip leading "./" and "/") and match exact OR
        # component-aligned suffix, so an absolute or differently-rooted touched
        # file still matches the repo-relative form manifests list. The "*/"
        # prefix keeps the match component-aligned (so "ab.sh" never matches
        # "cab.sh"). Fixes a silent unattributable on path-format drift (F1).
        norm_entry="${trimmed#./}";        norm_entry="${norm_entry#/}"
        norm_touched="${touched_file#./}"; norm_touched="${norm_touched#/}"

        if [[ "$norm_entry" == "$norm_touched" \
           || "$norm_entry" == */"$norm_touched" \
           || "$norm_touched" == */"$norm_entry" ]]; then
          # The canonical uuid (resolved above from the conforming filename) is
          # the task's globally-unique join key. Match it EXACTLY against
          # features.json .uuid — never a substring on T<NN>, which repeats
          # across milestones (M1.T01 and M2.T01 collide). Order-independent,
          # no head -1 ambiguity.
          owning_task="$(jq -r --arg u "$manifest_uuid" '
            .tasks[]
            | select(.uuid == $u)
            | .id
          ' "$features_file" 2>/dev/null || true)"

          break
        fi
      fi
    done < "$manifest"

    [[ -n "$owning_task" ]] && break
  done

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
# Emit record
# ---------------------------------------------------------------------------

# Normalize boolean strings to JSON booleans
_to_bool() {
  case "${1,,}" in
    true|1|yes) printf 'true' ;;
    *)          printf 'false' ;;
  esac
}

_emit_record \
  "$shape" \
  "$severity" \
  "$(_to_bool "$verifier_said_pass")" \
  "$(_to_bool "$review_found")"
