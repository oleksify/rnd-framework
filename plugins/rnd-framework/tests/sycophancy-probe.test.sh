#!/usr/bin/env bash
# Tests for lib/sycophancy-probe.sh — harness (prepare / ingest / summary).
# Usage: bash tests/sycophancy-probe.test.sh
# Exits 0 when all tests pass, 1 when any fail.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="${SCRIPT_DIR}/../lib/sycophancy-probe.sh"

# shellcheck source=./test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && git rev-parse --show-toplevel)"

# ---------------------------------------------------------------------------
# Fixture builder helpers
# ---------------------------------------------------------------------------

make_session() {
  local session_dir="$1"
  mkdir -p "${session_dir}/verifications"
}

make_verdict_map() {
  local path="$1"
  local content="$2"
  printf '%s' "$content" > "$path"
}

make_validation_contract() {
  local session_dir="$1"
  local assertion_id="$2"
  local text="$3"
  cat > "${session_dir}/validation-contract.md" <<CONTRACT
# Validation Contract

### ${assertion_id}

${text}

- Tool: grep
CONTRACT
}

# ---------------------------------------------------------------------------
# Fixture: one session with two PASS entries
#   - entry A: valid path at current HEAD (pinned_commit expected)
#   - entry B: bogus path absent at HEAD (head_fallback or drop expected)
# ---------------------------------------------------------------------------
printf '%s\n' '--- fixture setup ---'

FIXTURE_SESSION="${TMP_DIR}/slug/branches/main/sessions/20260101-120000-aabbccdd"
make_session "$FIXTURE_SESSION"

# Use a real path that definitely exists at HEAD
REAL_PATH="plugins/rnd-framework/lib/audit-event.sh"
HEAD_SHA="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
BOGUS_PATH="plugins/rnd-framework/lib/does-not-exist-fixture.xyz"

FIXTURE_MAP="${FIXTURE_SESSION}/verifications/wave-1-verdict-map.json"
make_verdict_map "$FIXTURE_MAP" "$(cat <<JSON
{
  "M1.fix.real-path": {
    "verdict": "PASS",
    "evidence": ["grep something ${REAL_PATH} → match found"],
    "feedback": "All checks passed for entry A."
  },
  "M1.fix.bogus-path": {
    "verdict": "PASS",
    "evidence": ["grep something ${BOGUS_PATH} → match found"],
    "feedback": "All checks passed for entry B."
  }
}
JSON
)"

make_validation_contract "$FIXTURE_SESSION" "M1.fix.real-path" \
  "The real-path assertion verifies ${REAL_PATH} exists and is correct."

SLUG_ROOT="${TMP_DIR}/slug"
PROBE_JSONL="${SLUG_ROOT}/sycophancy-probe.jsonl"

# ---------------------------------------------------------------------------
# 1. PREPARE phase
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- prepare: produces review inputs ---'

PREPARE_DIR="${TMP_DIR}/prepared"
bash "$HARNESS" prepare \
  --slug-root "${SLUG_ROOT}" \
  --repo-root "${REPO_ROOT}" \
  --output-dir "${PREPARE_DIR}" \
  2>/dev/null

n_prepared="$(ls "${PREPARE_DIR}"/*.json 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "prepare produces ≥1 review-input file" "true" "$([[ $n_prepared -ge 1 ]] && echo true || echo false)"

# ---------------------------------------------------------------------------
# 2. Barrier-clean: prepared inputs must NOT contain original feedback/evidence text
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- prepare: barrier-clean (no original verdict/feedback/evidence) ---'

# The feedback string from entry A
LEAKED_FEEDBACK="All checks passed for entry A."

grep_hit=0
grep -r "$LEAKED_FEEDBACK" "${PREPARE_DIR}" 2>/dev/null && grep_hit=1 || true
assert_eq "prepared inputs: original feedback not present" "0" "$grep_hit"

# The raw evidence citation string
LEAKED_EVIDENCE="grep something ${REAL_PATH} → match found"
grep_hit2=0
grep -r "$LEAKED_EVIDENCE" "${PREPARE_DIR}" 2>/dev/null && grep_hit2=1 || true
assert_eq "prepared inputs: original evidence strings not present" "0" "$grep_hit2"

# ---------------------------------------------------------------------------
# 3. git-show guard: no empty artifact body in prepared inputs
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- prepare: no empty artifact body for absent-path ---'

for input_file in "${PREPARE_DIR}"/*.json; do
  artifact="$(jq -r '.artifact // ""' "$input_file")"
  assert_eq "review-input has non-empty artifact ($(basename "$input_file"))" \
    "true" "$([[ -n "$artifact" ]] && echo true || echo false)"
done

# Confirm the bogus-path entry is either tagged head_fallback or counted as drop
bogus_basis="$(grep -l "M1.fix.bogus-path" "${PREPARE_DIR}"/*.json 2>/dev/null | head -1 || true)"
if [[ -n "$bogus_basis" ]]; then
  basis="$(jq -r '.artifact_basis' "$bogus_basis")"
  assert_eq "bogus-path entry tagged head_fallback" "head_fallback" "$basis"
fi

# ---------------------------------------------------------------------------
# 4. Session-id resolution: does NOT require task_id
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- prepare: session id from path (no task_id assumption) ---'

for input_file in "${PREPARE_DIR}"/*.json; do
  session_id="$(jq -r '.session_id' "$input_file")"
  assert_eq "session_id resolved ($(basename "$input_file"))" \
    "20260101-120000-aabbccdd" "$session_id"
done

# ---------------------------------------------------------------------------
# 5. INGEST phase: appends records with correct schema
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- ingest: appends record with new_verdict enum, no flipped bool ---'

# Build one synthetic verdict to ingest (simulating orchestrator output)
INGEST_INPUT="${TMP_DIR}/ingest-input.json"
first_input="$(ls "${PREPARE_DIR}"/*.json | head -1)"
assertion_ref="$(jq -r '.assertion_ref' "$first_input")"
session_id_val="$(jq -r '.session_id' "$first_input")"
commit_sha_val="$(jq -r '.commit_sha' "$first_input")"
artifact_basis_val="$(jq -r '.artifact_basis' "$first_input")"

jq -n \
  --arg ar "$assertion_ref" \
  --arg sid "$session_id_val" \
  --arg sha "$commit_sha_val" \
  --arg ab "$artifact_basis_val" \
  --arg nv "PASS_QUALITY_NEEDS_ITERATION" \
  '{assertion_ref: $ar, session_id: $sid, commit_sha: $sha, artifact_basis: $ab, new_verdict: $nv}' \
  > "$INGEST_INPUT"

bash "$HARNESS" ingest \
  --jsonl-path "${PROBE_JSONL}" \
  --record-file "${INGEST_INPUT}" \
  2>/dev/null

assert_eq "ingest: probe JSONL created" "true" "$([[ -f "$PROBE_JSONL" ]] && echo true || echo false)"

record="$(tail -1 "${PROBE_JSONL}")"

has_new_verdict="$(printf '%s' "$record" | jq -r 'if has("new_verdict") then "true" else "false" end')"
assert_eq "ingest: record has new_verdict" "true" "$has_new_verdict"

has_no_flipped="$(printf '%s' "$record" | jq -r 'if (has("flipped") | not) then "true" else "false" end')"
assert_eq "ingest: record has no flipped field" "true" "$has_no_flipped"

new_verdict_val="$(printf '%s' "$record" | jq -r '.new_verdict')"
assert_eq "ingest: new_verdict is valid enum" "PASS_QUALITY_NEEDS_ITERATION" "$new_verdict_val"

has_artifact_basis="$(printf '%s' "$record" | jq -r 'if has("artifact_basis") then "true" else "false" end')"
assert_eq "ingest: record has artifact_basis" "true" "$has_artifact_basis"

has_commit_sha="$(printf '%s' "$record" | jq -r 'if has("commit_sha") then "true" else "false" end')"
assert_eq "ingest: record has commit_sha" "true" "$has_commit_sha"

has_hard_flip="$(printf '%s' "$record" | jq -r 'if has("hard_flip") then "true" else "false" end')"
assert_eq "ingest: record has hard_flip" "true" "$has_hard_flip"

has_soft_flip="$(printf '%s' "$record" | jq -r 'if has("soft_flip") then "true" else "false" end')"
assert_eq "ingest: record has soft_flip" "true" "$has_soft_flip"

# Verify hard_flip derived correctly (PASS_QUALITY_NEEDS_ITERATION → soft=true, hard=false)
hard_flip_val="$(printf '%s' "$record" | jq -r '.hard_flip')"
soft_flip_val="$(printf '%s' "$record" | jq -r '.soft_flip')"
assert_eq "ingest: PASS_QUALITY → hard_flip=false" "false" "$hard_flip_val"
assert_eq "ingest: PASS_QUALITY → soft_flip=true" "true" "$soft_flip_val"

# ---------------------------------------------------------------------------
# 6. INGEST: hard flip record (FAIL → hard=true, soft=false)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- ingest: hard flip derivation ---'

FAIL_INGEST="${TMP_DIR}/fail-ingest.json"
jq -n \
  --arg ar "M1.fix.bogus-path" \
  --arg sid "20260101-120000-aabbccdd" \
  --arg sha "$commit_sha_val" \
  --arg ab "head_fallback" \
  --arg nv "FAIL" \
  '{assertion_ref: $ar, session_id: $sid, commit_sha: $sha, artifact_basis: $ab, new_verdict: $nv}' \
  > "$FAIL_INGEST"

bash "$HARNESS" ingest \
  --jsonl-path "${PROBE_JSONL}" \
  --record-file "${FAIL_INGEST}" \
  2>/dev/null

fail_record="$(tail -1 "${PROBE_JSONL}")"
fail_hard="$(printf '%s' "$fail_record" | jq -r '.hard_flip')"
fail_soft="$(printf '%s' "$fail_record" | jq -r '.soft_flip')"
assert_eq "ingest: FAIL → hard_flip=true" "true" "$fail_hard"
assert_eq "ingest: FAIL → soft_flip=false" "false" "$fail_soft"

# ---------------------------------------------------------------------------
# 7. SUMMARY phase (completeness line format)
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- summary: completeness and basis-split lines ---'

SUMMARY_OUTPUT="$(bash "$HARNESS" summary --jsonl-path "${PROBE_JSONL}" 2>/dev/null)"

assert_contains "summary: has corpus= line" "corpus=" "$SUMMARY_OUTPUT"
assert_contains "summary: has reviewed= in completeness" "reviewed=" "$SUMMARY_OUTPUT"
assert_contains "summary: has dropped= in completeness" "dropped=" "$SUMMARY_OUTPUT"
assert_contains "summary: has pinned_commit=" "pinned_commit=" "$SUMMARY_OUTPUT"
assert_contains "summary: has head_fallback=" "head_fallback=" "$SUMMARY_OUTPUT"

# Verify N = reviewed + dropped (extract and compute)
corpus_n="$(printf '%s' "$SUMMARY_OUTPUT" | grep -oE 'corpus=[0-9]+' | head -1 | grep -oE '[0-9]+')"
reviewed_m="$(printf '%s' "$SUMMARY_OUTPUT" | grep -oE 'reviewed=[0-9]+' | head -1 | grep -oE '[0-9]+')"
dropped_k="$(printf '%s' "$SUMMARY_OUTPUT" | grep -oE 'dropped=[0-9]+' | head -1 | grep -oE '[0-9]+')"

computed_n="$(( reviewed_m + dropped_k ))"
assert_eq "summary: corpus = reviewed + dropped" "$corpus_n" "$computed_n"

# ---------------------------------------------------------------------------
# 8. Schema validation: jq check on all records in probe JSONL
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- schema: new_verdict present, flipped absent ---'

all_pass=0
bad_count=0
while IFS= read -r line; do
  ok="$(printf '%s' "$line" | jq -e 'has("new_verdict") and (has("flipped") | not)' > /dev/null && echo ok || echo bad)"
  if [[ "$ok" != "ok" ]]; then
    bad_count=$(( bad_count + 1 ))
  fi
done < "${PROBE_JSONL}"

assert_eq "schema: all records pass new_verdict+no-flipped check" "0" "$bad_count"

# ---------------------------------------------------------------------------
# 9. resolve_commit_for_session (FM6 risk surface): selection + HEAD fallback
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- resolve_commit_for_session: selection and HEAD fallback ---'

# Throwaway git repo with two commits.
RC_REPO="${TMP_DIR}/rc-repo"
mkdir -p "$RC_REPO"
git -C "$RC_REPO" init -q
git -C "$RC_REPO" config user.email "t@t.t"
git -C "$RC_REPO" config user.name "t"
printf 'a\n' > "${RC_REPO}/f.txt"; git -C "$RC_REPO" add f.txt; git -C "$RC_REPO" commit -q -m c1
printf 'b\n' >> "${RC_REPO}/f.txt"; git -C "$RC_REPO" add f.txt; git -C "$RC_REPO" commit -q -m c2

RC_HEAD="$(git -C "$RC_REPO" rev-parse HEAD)"
RC_ROOT_COMMIT="$(git -C "$RC_REPO" rev-list --max-parents=0 HEAD)"

# Source the harness to expose the pure helper (source-guard prevents main running).
source "$HARNESS"

RC_MAP="${TMP_DIR}/rc-map.json"
printf '{}' > "$RC_MAP"

# (a) map mtime far in the future → no commit's author-time >= mtime → HEAD fallback.
touch -t 209901010000 "$RC_MAP"
rc_future="$(resolve_commit_for_session "$RC_MAP" "$RC_REPO")"
assert_eq "resolve: future mtime falls back to HEAD" "$RC_HEAD" "$rc_future"

# (b) map mtime older than all commits → earliest qualifying commit (the root).
touch -t 197001020000 "$RC_MAP"
rc_old="$(resolve_commit_for_session "$RC_MAP" "$RC_REPO")"
assert_eq "resolve: old mtime selects the earliest commit after it (root)" "$RC_ROOT_COMMIT" "$rc_old"

# ---------------------------------------------------------------------------
# 10. INGEST: rationale field passthrough
# ---------------------------------------------------------------------------
printf '\n%s\n' '--- ingest: rationale field passthrough ---'

RATIONALE_JSONL="${TMP_DIR}/rationale-probe.jsonl"

# (a) record-file WITH rationale → emitted record carries the rationale text
RATIONALE_INPUT="${TMP_DIR}/rationale-with.json"
jq -n \
  --arg ar "M1.fix.real-path" \
  --arg sid "20260101-120000-aabbccdd" \
  --arg sha "$commit_sha_val" \
  --arg ab "pinned_commit" \
  --arg nv "FAIL" \
  --arg rat "The artifact no longer contains the expected function." \
  '{assertion_ref: $ar, session_id: $sid, commit_sha: $sha, artifact_basis: $ab, new_verdict: $nv, rationale: $rat}' \
  > "$RATIONALE_INPUT"

bash "$HARNESS" ingest \
  --jsonl-path "${RATIONALE_JSONL}" \
  --record-file "${RATIONALE_INPUT}" \
  2>/dev/null

rat_record="$(tail -1 "${RATIONALE_JSONL}")"
has_rationale="$(printf '%s' "$rat_record" | jq -r 'if has("rationale") then "true" else "false" end')"
assert_eq "ingest: record has rationale field" "true" "$has_rationale"

rationale_val="$(printf '%s' "$rat_record" | jq -r '.rationale')"
assert_eq "ingest: rationale value passed through" "The artifact no longer contains the expected function." "$rationale_val"

# (b) record-file WITHOUT rationale → emitted record has rationale:""
RATIONALE_ABSENT="${TMP_DIR}/rationale-absent.json"
jq -n \
  --arg ar "M1.fix.bogus-path" \
  --arg sid "20260101-120000-aabbccdd" \
  --arg sha "$commit_sha_val" \
  --arg ab "head_fallback" \
  --arg nv "PASS" \
  '{assertion_ref: $ar, session_id: $sid, commit_sha: $sha, artifact_basis: $ab, new_verdict: $nv}' \
  > "$RATIONALE_ABSENT"

bash "$HARNESS" ingest \
  --jsonl-path "${RATIONALE_JSONL}" \
  --record-file "${RATIONALE_ABSENT}" \
  2>/dev/null

absent_record="$(tail -1 "${RATIONALE_JSONL}")"
absent_rationale="$(printf '%s' "$absent_record" | jq -r '.rationale')"
assert_eq "ingest: absent rationale defaults to empty string" "" "$absent_rationale"

# ---------------------------------------------------------------------------
report
