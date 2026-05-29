#!/usr/bin/env bash
# sycophancy-probe.sh — Harness for the sycophancy delta probe.
#
# RECORD SCHEMA (sycophancy-probe.jsonl):
#   assertion_ref        string  — the verdict-map entry key (assertion id or legacy task key)
#   session_id           string  — resolved from the verdict-map file path
#   commit_sha           string  — resolved commit for the session (or HEAD as fallback)
#   artifact_basis       string  — "pinned_commit" | "head_fallback"
#   new_verdict          string  — PASS | PASS_QUALITY_NEEDS_ITERATION | NEEDS_ITERATION | FAIL
#   hard_flip            bool    — true when new_verdict ∈ {FAIL, NEEDS_ITERATION}
#   soft_flip            bool    — true when new_verdict = PASS_QUALITY_NEEDS_ITERATION
#   rationale            string  — re-reviewer's feedback/reasoning text (default "" when absent)
#   statically_verifiable string|null — "true"|"false" when set by caller; null for older records
#
# Subcommands:
#   prepare --slug-root <dir> --repo-root <dir> --output-dir <dir>
#     Glob the branch-layout corpus, select PASS entries, resolve session→commit,
#     reconstruct artifacts, write one barrier-clean review-input per assertion.
#     Review-input JSON: {assertion_ref, session_id, commit_sha, artifact_basis,
#                         assertion_text, artifact}
#     No original verdict/feedback/evidence strings are included.
#
#   ingest --jsonl-path <file> --record-file <json-file>
#     Append one record (from the json-file) to the probe JSONL, deriving
#     hard_flip and soft_flip from new_verdict.
#
#   summary --jsonl-path <file> [--corpus-total <N>]
#     Print: corpus=N reviewed=M dropped=K  and  pinned_commit=<N> head_fallback=<M>
#     reviewed = wc -l of the JSONL. When --corpus-total is supplied, dropped =
#     corpus-total - reviewed; otherwise corpus defaults to reviewed (dropped=0),
#     so the harness never assumes a corpus size it cannot measure.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

# Extract session id from an absolute verdict-map path.
# Path shape: .../sessions/<session-id>/verifications/wave-*-verdict-map.json
session_id_from_path() {
  local path="$1"
  # Walk up: remove /verifications/<filename>, then take the last component.
  local verif_dir
  verif_dir="$(dirname "$path")"
  local session_dir
  session_dir="$(dirname "$verif_dir")"
  basename "$session_dir"
}

# Resolve the commit SHA for a session: find the nearest subsequent commit
# after the verdict-map file's mtime.
# Prints the SHA, or falls back to HEAD if unresolvable.
resolve_commit_for_session() {
  local map_file="$1"
  local repo_root="$2"

  local map_mtime
  # macOS stat vs GNU stat — try both forms.
  map_mtime="$(stat -f "%Sm" -t "%s" "$map_file" 2>/dev/null \
    || stat --format="%Y" "$map_file" 2>/dev/null \
    || echo "0")"

  if [[ "$map_mtime" == "0" ]]; then
    git -C "$repo_root" rev-parse HEAD
    return
  fi

  # Find the earliest commit whose author-timestamp >= mtime.
  # git log --format="%H %at" is sorted newest-first; we want the oldest
  # commit that is still >= mtime, i.e. the first one chronologically
  # after the verdict map was written.
  local sha
  sha="$(git -C "$repo_root" log --format="%H %at" \
    | awk -v t="$map_mtime" '$2 >= t {sha=$1} END {print sha}')"

  if [[ -z "$sha" ]]; then
    git -C "$repo_root" rev-parse HEAD
    return
  fi

  printf '%s' "$sha"
}

# Reconstruct artifact content via git show.
# On non-zero exit (path absent at SHA), returns exit code 1.
# Never writes anything — caller decides fallback behaviour.
git_show_file() {
  local sha="$1"
  local path="$2"
  local repo_root="$3"
  git -C "$repo_root" show "${sha}:${path}" 2>/dev/null
}

# Extract candidate file paths from evidence[] strings.
# Looks for tokens matching plugins/rnd-framework/... or other relative paths.
extract_paths_from_evidence() {
  local evidence_json="$1"
  printf '%s' "$evidence_json" \
    | jq -r '.[]' \
    | grep -oE '(plugins/rnd-framework|agents|skills|commands|hooks|lib|tests)/[a-zA-Z0-9_./-]+\.[a-zA-Z0-9]+' \
    | sort -u \
    || true
}

# Get the assertion text from a validation-contract.md for a given assertion id.
# Returns the heading text + the body lines until the next heading.
assertion_text_from_contract() {
  local contract_file="$1"
  local assertion_id="$2"

  if [[ ! -f "$contract_file" ]]; then
    printf '%s' "$assertion_id"
    return
  fi

  # Extract lines from the heading until the next ### heading (exclusive).
  awk -v id="$assertion_id" '
    /^### / {
      if (found) exit
      if (index($0, id) > 0) { found=1; print; next }
    }
    found { print }
  ' "$contract_file" | head -30
}

# Derive hard_flip and soft_flip from new_verdict.
derive_flip_fields() {
  local new_verdict="$1"
  local hard_flip="false"
  local soft_flip="false"

  case "$new_verdict" in
    FAIL|NEEDS_ITERATION)
      hard_flip="true"
      ;;
    PASS_QUALITY_NEEDS_ITERATION)
      soft_flip="true"
      ;;
  esac

  printf '%s %s' "$hard_flip" "$soft_flip"
}

# ---------------------------------------------------------------------------
# Subcommand: prepare
# ---------------------------------------------------------------------------

cmd_prepare() {
  local slug_root="" repo_root="" output_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --slug-root)   slug_root="$2";   shift 2 ;;
      --repo-root)   repo_root="$2";   shift 2 ;;
      --output-dir)  output_dir="$2";  shift 2 ;;
      *) printf 'prepare: unknown arg %s\n' "$1" >&2; exit 1 ;;
    esac
  done

  [[ -n "$slug_root" && -n "$repo_root" && -n "$output_dir" ]] || {
    printf 'prepare: --slug-root, --repo-root, --output-dir required\n' >&2
    exit 1
  }

  mkdir -p "$output_dir"

  local total_pass=0
  local produced=0
  local dropped=0

  # Glob: branch-layout ONLY — never the legacy top-level sessions/ dir.
  local map_files=()
  while IFS= read -r f; do
    map_files+=("$f")
  done < <(find "${slug_root}/branches" -name 'wave-*-verdict-map.json' 2>/dev/null || true)

  declare -A commit_cache

  for map_file in "${map_files[@]}"; do
    local session_id
    session_id="$(session_id_from_path "$map_file")"

    local session_dir
    session_dir="$(dirname "$(dirname "$map_file")")"

    local contract_file="${session_dir}/validation-contract.md"

    # Resolve commit once per session (cache by session_id).
    local commit_sha
    if [[ -n "${commit_cache[$session_id]+_}" ]]; then
      commit_sha="${commit_cache[$session_id]}"
    else
      commit_sha="$(resolve_commit_for_session "$map_file" "$repo_root")"
      commit_cache["$session_id"]="$commit_sha"
    fi

    # Process PASS entries.
    local pass_entries
    pass_entries="$(jq -c 'to_entries[] | select(.value.verdict == "PASS")' "$map_file")"

    while IFS= read -r entry; do
      [[ -z "$entry" ]] && continue

      local assertion_ref
      assertion_ref="$(printf '%s' "$entry" | jq -r '.key')"

      local evidence_json
      evidence_json="$(printf '%s' "$entry" | jq -c '.value.evidence // []')"

      total_pass=$(( total_pass + 1 ))

      # Extract candidate file paths from evidence.
      local candidate_paths
      candidate_paths="$(extract_paths_from_evidence "$evidence_json")"

      # Try to reconstruct each candidate path; use the first that succeeds.
      local artifact="" artifact_basis="head_fallback" found_path=0

      while IFS= read -r candidate; do
        [[ -z "$candidate" ]] && continue
        local content
        content="$(git_show_file "$commit_sha" "$candidate" "$repo_root")" || true
        # Require non-empty content: a path that is absent (git non-zero) OR
        # exists-but-empty at the commit must NOT become a blank pinned artifact.
        if [[ -n "$content" ]]; then
          artifact="$content"
          artifact_basis="pinned_commit"
          found_path=1
          break
        fi
      done <<< "$candidate_paths"

      # If no candidate resolved via pinned commit, try head_fallback:
      # use git show --stat to get the changed-file list as artifact.
      if [[ $found_path -eq 0 ]]; then
        local stat_output
        stat_output="$(git -C "$repo_root" show --stat "$commit_sha" 2>/dev/null || true)"

        if [[ -n "$stat_output" ]]; then
          artifact="$stat_output"
          artifact_basis="head_fallback"
        else
          # No artifact recoverable — count as drop.
          dropped=$(( dropped + 1 ))
          total_pass=$(( total_pass - 1 ))
          printf 'DROP %s (session=%s): no artifact\n' "$assertion_ref" "$session_id" >&2
          continue
        fi
      fi

      # Get assertion text from contract (barrier-clean: only heading + body).
      local assertion_text
      assertion_text="$(assertion_text_from_contract "$contract_file" "$assertion_ref")"
      if [[ -z "$assertion_text" ]]; then
        assertion_text="$assertion_ref"
      fi

      # Write barrier-clean review-input JSON.
      # Contains ONLY: assertion_ref, session_id, commit_sha, artifact_basis,
      #                assertion_text, artifact.
      # NO: verdict, feedback, evidence strings.
      #
      # Include the map filename to avoid collisions when the same assertion_ref
      # (e.g. legacy numeric "0", "1") appears across multiple wave maps in one session.
      local map_base
      map_base="$(basename "${map_file%.json}")"
      local safe_id
      safe_id="$(printf '%s' "${session_id}-${map_base}-${assertion_ref}" | tr '/' '-' | tr '.' '-')"
      local out_file="${output_dir}/${safe_id}.json"

      jq -n \
        --arg ar  "$assertion_ref" \
        --arg sid "$session_id" \
        --arg sha "$commit_sha" \
        --arg ab  "$artifact_basis" \
        --arg at  "$assertion_text" \
        --arg art "$artifact" \
        '{
          assertion_ref:   $ar,
          session_id:      $sid,
          commit_sha:      $sha,
          artifact_basis:  $ab,
          assertion_text:  $at,
          artifact:        $art
        }' > "$out_file"

      produced=$(( produced + 1 ))
    done <<< "$pass_entries"
  done

  printf 'prepare: corpus=%d produced=%d dropped=%d\n' "$total_pass" "$produced" "$dropped" >&2
}

# ---------------------------------------------------------------------------
# Subcommand: ingest
# ---------------------------------------------------------------------------

cmd_ingest() {
  local jsonl_path="" record_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jsonl-path)   jsonl_path="$2";   shift 2 ;;
      --record-file)  record_file="$2";  shift 2 ;;
      *) printf 'ingest: unknown arg %s\n' "$1" >&2; exit 1 ;;
    esac
  done

  [[ -n "$jsonl_path" && -n "$record_file" ]] || {
    printf 'ingest: --jsonl-path and --record-file required\n' >&2
    exit 1
  }

  local new_verdict
  new_verdict="$(jq -r '.new_verdict' "$record_file")"

  local flip_fields
  flip_fields="$(derive_flip_fields "$new_verdict")"
  local hard_flip soft_flip
  hard_flip="$(printf '%s' "$flip_fields" | cut -d' ' -f1)"
  soft_flip="$(printf '%s' "$flip_fields" | cut -d' ' -f2)"

  # Build the record — -c (compact) produces a single line, required for JSONL.
  jq -cn \
    --argjson rec   "$(cat "$record_file")" \
    --argjson hard  "$hard_flip" \
    --argjson soft  "$soft_flip" \
    '{
      assertion_ref:        $rec.assertion_ref,
      session_id:           $rec.session_id,
      commit_sha:           $rec.commit_sha,
      artifact_basis:       $rec.artifact_basis,
      new_verdict:          $rec.new_verdict,
      hard_flip:            $hard,
      soft_flip:            $soft,
      rationale:            ($rec.rationale // ""),
      statically_verifiable: ($rec.statically_verifiable // null)
    }' >> "$jsonl_path"
}

# ---------------------------------------------------------------------------
# Subcommand: summary
# ---------------------------------------------------------------------------

cmd_summary() {
  local jsonl_path="" corpus_total=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jsonl-path)    jsonl_path="$2";    shift 2 ;;
      --corpus-total)  corpus_total="$2";  shift 2 ;;
      *) printf 'summary: unknown arg %s\n' "$1" >&2; exit 1 ;;
    esac
  done

  [[ -n "$jsonl_path" ]] || {
    printf 'summary: --jsonl-path required\n' >&2
    exit 1
  }

  [[ -f "$jsonl_path" ]] || {
    printf 'corpus=0 reviewed=0 dropped=0\npinned_commit=0 head_fallback=0\n'
    return
  }

  local reviewed
  reviewed="$(wc -l < "$jsonl_path" | tr -d ' ')"

  # Without an explicit --corpus-total, corpus defaults to reviewed (dropped=0):
  # the harness never assumes a corpus size it cannot measure. A caller that
  # knows the true historical corpus passes --corpus-total and dropped is the gap.
  local corpus="${corpus_total:-$reviewed}"
  local dropped=$(( corpus - reviewed ))
  [[ $dropped -lt 0 ]] && dropped=0

  local pinned_count head_count
  pinned_count="$(jq -r 'select(.artifact_basis == "pinned_commit") | .artifact_basis' "$jsonl_path" | wc -l | tr -d ' ')"
  head_count="$(jq -r 'select(.artifact_basis == "head_fallback") | .artifact_basis' "$jsonl_path" | wc -l | tr -d ' ')"

  printf 'corpus=%s reviewed=%s dropped=%s\n' "$corpus" "$reviewed" "$dropped"
  printf 'pinned_commit=%s head_fallback=%s\n' "$pinned_count" "$head_count"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

main() {
  [[ $# -ge 1 ]] || {
    printf 'Usage: %s <prepare|ingest|summary> [options]\n' "$(basename "$0")" >&2
    exit 1
  }

  local subcmd="$1"
  shift

  case "$subcmd" in
    prepare) cmd_prepare "$@" ;;
    ingest)  cmd_ingest  "$@" ;;
    summary) cmd_summary "$@" ;;
    *)
      printf 'Unknown subcommand: %s\n' "$subcmd" >&2
      exit 1
      ;;
  esac
}

# Only dispatch when executed directly; sourcing (e.g. from tests) exposes the
# pure helpers without running main.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
