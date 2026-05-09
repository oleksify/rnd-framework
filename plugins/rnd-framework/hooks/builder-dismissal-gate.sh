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
manifests=()
if compgen -G "${session_dir}/builds/T*-manifest.md" > /dev/null 2>&1; then
  while IFS= read -r f; do
    manifests+=("$f")
  done < <(ls -t "${session_dir}/builds/"T*-manifest.md 2>/dev/null)
fi

if [[ "${#manifests[@]}" -eq 0 ]]; then
  exit 0
fi

manifest_path="${manifests[0]}"

# Extract task ID from filename: T1-manifest.md → T1
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
# ---------------------------------------------------------------------------

has_problem_language=0

for term in "failure" "error" "broken" "bug" "issue"; do
  if [[ "$lower" == *"$term"* ]]; then
    has_problem_language=1
    break
  fi
done

if [[ "$has_problem_language" -eq 1 ]]; then
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

exit 0
