#!/usr/bin/env bash
# hooks/builder-dismissal-gate.sh — SubagentStop hook.
# Blocks the rnd-builder agent from completing when its build manifest contains
# dismissal-licensing phrases or acknowledged-but-unaddressed failures.
# Exits 2 (block) on violation; exits 0 (no-opinion) for all other agents or
# when no active session / manifest is found.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

raw="$(cat)"

agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

agent_lower="$(_lower "$agent_type")"

if [[ "$agent_lower" != *"rnd-builder"* ]]; then
  exit 0
fi

session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -z "$session_dir" ]]; then
  exit 0
fi

# Locate the most recent build manifest in builds/
# Matches both current M<NN>-T<NN>-<uuid>-manifest.md and legacy T<id>-manifest.md forms.
manifests=()
if compgen -G "${session_dir}/builds/*-manifest.md" > /dev/null 2>&1; then
  while IFS= read -r f; do
    manifests+=("$f")
  done < <(ls -t "${session_dir}/builds/"*-manifest.md 2>/dev/null)
fi

if [[ "${#manifests[@]}" -eq 0 ]]; then
  exit 0
fi

manifest_path="${manifests[0]}"

# Extract task ID from filename (both forms): T1-manifest.md → T1; M02-T03-f6d3915b-manifest.md → M02-T03-f6d3915b
manifest_base="${manifest_path##*/}"
task_id="${manifest_base%-manifest.md}"

ledger="${session_dir}/builds/${task_id}-found-issues.jsonl"

manifest_content="$(< "$manifest_path")"
lower="$(_lower "$manifest_content")"

# ---------------------------------------------------------------------------
# Check A: dismissal-licensing phrase scan
# ---------------------------------------------------------------------------

for phrase in "pre-existing" "out of scope" "not my task" "unrelated to this task" "won't fix here" "outside scope"; do
  if [[ "$lower" == *"$phrase"* ]]; then
    block_msg "builder-dismissal-gate: manifest contains dismissal phrase \"${phrase}\".

Dismissal is not permitted. You have two paths:
  1. Fix the issue in this build.
  2. Append a JSON entry to the found-issues ledger documenting your decision:
       ${ledger}
     Format: {\"issue\":\"...\",\"location\":\"...\",\"decision\":\"escalated\",\"reason\":\"...\"}

Remove the phrase \"${phrase}\" from the manifest and choose one of the two paths."
  fi
done

# ---------------------------------------------------------------------------
# Check B: acknowledged-but-unfixed scan
#
# Blocks when a problem term (failure/error/broken/bug/issue) appears on a
# line without a co-occurring resolution marker. A line is benign when the
# term is paired with: "fixed", "resolved" (but not "unresolved"), "handling"
# (as in error-handling feature), "addressed", "no <term>" (e.g. "no issues"),
# or "<term> #<N>" (a tracker reference like "issue #42"). Any line that
# contains a problem term without one of these markers is treated as an
# acknowledged-but-unfixed problem that requires a ledger entry.
# ---------------------------------------------------------------------------

has_unresolved_problem=0

_check_b_line_benign() {
  local line="$1" term="$2"
  [[ "$line" == *"fixed"*    ]] && return 0
  # "resolved" but not "unresolved" — avoid substring false match
  if [[ "$line" == *"resolved"* ]] && [[ "$line" != *"unresolved"* ]]; then return 0; fi
  [[ "$line" == *"handling"* ]] && return 0
  [[ "$line" == *"addressed"* ]] && return 0
  # "no <term>": "no issues", "no errors"
  [[ "$line" == *"no $term"* ]] && return 0
  # tracker reference: "issue #42", "bug #7"
  [[ "$line" == *"$term #"* ]] && return 0
  return 1
}

while IFS= read -r manifest_line; do
  line_lower="$(_lower "$manifest_line")"

  for term in "failure" "error" "broken" "bug" "issue"; do
    if [[ "$line_lower" != *"$term"* ]]; then
      continue
    fi

    if _check_b_line_benign "$line_lower" "$term"; then
      continue
    fi

    has_unresolved_problem=1
    break
  done

  [[ "$has_unresolved_problem" -eq 1 ]] && break
done <<< "$manifest_content"

if [[ "$has_unresolved_problem" -eq 1 ]]; then
  ledger_has_entries=0

  if [[ -f "$ledger" ]]; then
    nonempty_count="$(grep -c '[^[:space:]]' "$ledger" 2>/dev/null || true)"

    if [[ "${nonempty_count:-0}" -gt 0 ]]; then
      ledger_has_entries=1
    fi
  fi

  if [[ "$ledger_has_entries" -eq 0 ]]; then
    block_msg "builder-dismissal-gate: manifest acknowledges problems (\"failure\"/\"error\"/\"broken\"/\"bug\"/\"issue\") but no entries exist in the found-issues ledger:
  ${ledger}

For each acknowledged issue, either:
  1. Fix it and update the manifest.
  2. Append an entry to the ledger: {\"issue\":\"...\",\"location\":\"...\",\"decision\":\"escalated\",\"reason\":\"...\"}"
  fi
fi

# ---------------------------------------------------------------------------
# Check C: ledger required when DONE/DONE_WITH_CONCERNS + failure terms
# ---------------------------------------------------------------------------

has_done_status=0

if [[ "$lower" == *"status: done"* ]]; then
  has_done_status=1
fi

if [[ "$lower" == *"status: done_with_concerns"* ]]; then
  has_done_status=1
fi

if [[ "$has_done_status" -eq 1 ]]; then
  has_fail_term=0

  if [[ "$lower" == *"fail"* || "$lower" == *"failed"* ]]; then
    has_fail_term=1
  fi

  if [[ "$has_fail_term" -eq 1 ]]; then
    ledger_present=0

    if [[ -f "$ledger" ]]; then
      nonempty_count="$(grep -c '[^[:space:]]' "$ledger" 2>/dev/null || true)"

      if [[ "${nonempty_count:-0}" -gt 0 ]]; then
        ledger_present=1
      fi
    fi

    if [[ "$ledger_present" -eq 0 ]]; then
      block_msg "builder-dismissal-gate: manifest claims build is complete (DONE/DONE_WITH_CONCERNS) but contains failure terms with no found-issues ledger:
  ${ledger}

Append at least one entry documenting each acknowledged failure before completing:
  {\"issue\":\"...\",\"location\":\"...\",\"decision\":\"escalated\",\"reason\":\"...\"}"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Check D: DONE re-submission must carry non-empty Verifier evidence
#
# Rationale: the evidence directory only exists after the Verifier has run at
# least one cycle (it writes per-VAL evidence files on FAIL / NEEDS_ITERATION).
# On a first build the directory does not exist and Check D is a no-op. On
# re-submission the directory exists, and we require at least one non-empty
# VAL-*.txt file as a structural witness that the Builder addressed Verifier
# feedback rather than re-declaring DONE with placeholder/empty files.
#
# A bare existence check (compgen -G) would let a Builder bypass the gate
# with `touch evidence_dir/VAL-bypass.txt`. The `-s` check forces the file
# to carry content.
# ---------------------------------------------------------------------------

if [[ "$has_done_status" -eq 1 ]]; then
  evidence_dir="${session_dir}/verifications/${task_id}-evidence"

  if [[ -d "$evidence_dir" ]]; then
    has_non_empty_val=0
    shopt -s nullglob
    for val_file in "${evidence_dir}"/VAL-*.txt; do
      if [[ -s "$val_file" ]]; then
        has_non_empty_val=1
        break
      fi
    done
    shopt -u nullglob

    if [[ "$has_non_empty_val" -eq 0 ]]; then
      block_msg "builder-dismissal-gate: manifest is DONE/DONE_WITH_CONCERNS but the evidence directory has no non-empty VAL-*.txt files:
  ${evidence_dir}

A prior verification cycle created this directory; re-submitting DONE without producing at least one non-empty VAL-*.txt evidence file is not permitted (empty files do not satisfy the gate).

Either:
  1. Run verification first and let the Verifier write evidence files, then re-submit.
  2. Produce at least one non-empty VAL-*.txt file in the evidence directory documenting the criterion that was addressed before re-submitting DONE."
    fi
  fi
fi

exit 0
