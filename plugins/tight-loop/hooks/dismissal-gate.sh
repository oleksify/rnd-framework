#!/usr/bin/env bash
# hooks/dismissal-gate.sh — Stop hook.
# Reads the most recent assistant message from the Stop event JSON.
# If no <final-report> marker is present → exit 0 (no-op).
# If marker is present:
#   (a) Scan for dismissal phrases → exit 2 if found.
#   (b) Scan for problem terms; if found and no valid ledger → exit 2.
#   (c) All clear → exit 0.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

raw="$(cat)"

# ---------------------------------------------------------------------------
# Extract content from the Stop event.
# content may be a string OR an array of {type,text} blocks.
# ---------------------------------------------------------------------------

content_type="$(printf '%s' "$raw" | jq -r '.message.content | type' 2>/dev/null || true)"

if [[ "$content_type" == "string" ]]; then
  content="$(printf '%s' "$raw" | jq -r '.message.content // ""' 2>/dev/null || true)"
elif [[ "$content_type" == "array" ]]; then
  content="$(printf '%s' "$raw" | jq -r '[.message.content[] | select(.type == "text") | .text] | join("")' 2>/dev/null || true)"
else
  content=""
fi

# ---------------------------------------------------------------------------
# Gate: only proceed if <final-report> marker is present
# ---------------------------------------------------------------------------

if [[ "$content" != *"<final-report>"* ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve tight-loop base directory.
# Tests may override via TIGHT_LOOP_BASE_DIR_OVERRIDE to bypass slug computation.
# ---------------------------------------------------------------------------

if [[ -n "${TIGHT_LOOP_BASE_DIR_OVERRIDE:-}" ]]; then
  base_dir="$TIGHT_LOOP_BASE_DIR_OVERRIDE"
else
  base_dir="$(tight_base_dir 2>/dev/null || true)"
fi

if [[ -z "$base_dir" || ! -d "$base_dir" ]]; then
  exit 0
fi

ledger="${base_dir}/found-issues.jsonl"

lower="$(_lower "$content")"

# ---------------------------------------------------------------------------
# Check A: dismissal phrase scan
# ---------------------------------------------------------------------------

for phrase in "pre-existing" "out of scope" "not my task" "unrelated to this task" "won't fix here" "outside scope"; do
  if [[ "$lower" == *"$phrase"* ]]; then
    block_msg "dismissal-gate: final-report contains dismissal phrase \"${phrase}\".

Dismissal is not permitted. You have two paths:
  1. Fix the issue in this task.
  2. Append a JSON entry to the found-issues ledger documenting your decision:
       ${ledger}
     Format: {\"issue\":\"...\",\"location\":\"...\",\"decision\":\"escalated\",\"reason\":\"...\"}

Remove the phrase \"${phrase}\" from the final-report and choose one of the two paths."
  fi
done

# ---------------------------------------------------------------------------
# Check B: problem term scan — requires a ledger with at least one valid entry
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
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "${line//[[:space:]]/}" ]] && continue

      if printf '%s' "$line" | jq -e 'type == "object"' >/dev/null 2>&1; then
        ledger_has_entries=1
        break
      fi
    done < "$ledger"
  fi

  if [[ "$ledger_has_entries" -eq 0 ]]; then
    block_msg "dismissal-gate: final-report mentions problems (\"failure\"/\"error\"/\"broken\"/\"bug\"/\"issue\") but no entries exist in the found-issues ledger:
  ${ledger}

For each acknowledged issue, either:
  1. Fix it and ensure the final-report reflects the fix.
  2. Append an entry to the ledger:
       {\"issue\":\"...\",\"location\":\"...\",\"decision\":\"escalated\",\"reason\":\"...\"}"
  fi
fi

exit 0
