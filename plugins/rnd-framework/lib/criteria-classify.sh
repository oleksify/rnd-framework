#!/usr/bin/env bash
# criteria-classify.sh — Classify a pre-reg's Correctness criteria as
# mechanical vs judgment and recommend a Verification level.
#
# Usage:
#   criteria-classify.sh <pre-reg-path>
#   criteria-classify.sh --help
#
# Output (stdout): JSON object
#   {"mechanical_pct":<int>,"judgment_pct":<int>,"recommended_level":"inline"|"unit"|"system"}
#
# Recommendation thresholds:
#   mechanical_pct >= 80 → inline
#   mechanical_pct >= 40 → unit
#   else                 → system
#
# Mechanical patterns (case-insensitive substring match):
#   grep, jq, exit code, exits 0, file exists, wc -l, find, returns ≥,
#   returns at least, test.sh exits, bash.*\.test\.sh.*exits

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_usage() {
  printf 'Usage: criteria-classify.sh <pre-reg-path>\n\n'
  printf 'Reads a pre-registration file, extracts the Correctness: checklist,\n'
  printf 'and classifies each item as mechanical or judgment.\n\n'
  printf 'Output JSON:\n'
  printf '  {"mechanical_pct":<int>,"judgment_pct":<int>,"recommended_level":"inline"|"unit"|"system"}\n\n'
  printf 'Recommendation thresholds:\n'
  printf '  mechanical_pct >= 80  →  inline\n'
  printf '  mechanical_pct >= 40  →  unit\n'
  printf '  else                  →  system\n'
}

if [[ "${1:-}" == "--help" ]]; then
  _usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  printf 'Error: pre-reg path required\n' >&2
  _usage >&2
  exit 1
fi

_PREREG_PATH="$1"

if [[ ! -f "$_PREREG_PATH" ]]; then
  printf 'Error: file not found: %s\n' "$_PREREG_PATH" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Single awk pass:
#   1. Detect entry into the Correctness: section (## Correctness line).
#   2. Collect every "- [ ]" item until the next "## " heading.
#   3. For each item, lowercase + check against mechanical-pattern set.
#   4. Compute pcts and apply thresholds.
#   5. Print JSON to stdout.
# ---------------------------------------------------------------------------

awk '
  BEGIN {
    in_correctness = 0
    total   = 0
    mech    = 0
  }

  # Enter Correctness section — both forms:
  #   (a) "## Correctness" (markdown header, test fixtures)
  #   (b) indented "  Correctness:" (real pre-reg format inside Success criteria block)
  /^##[[:space:]]+(Correctness)[[:space:]]*:?[[:space:]]*$/ {
    in_correctness = 1
    next
  }
  /^[[:space:]]+Correctness:[[:space:]]*$/ {
    in_correctness = 1
    next
  }

  # Exit Correctness section on:
  #   (a) any other "## " heading
  #   (b) sibling field at same indent (e.g., "  Quality:", "  Verification level:")
  in_correctness && /^##[[:space:]]/ {
    in_correctness = 0
    next
  }
  in_correctness && /^[[:space:]]+[A-Z][a-zA-Z ]*:[[:space:]]*$/ {
    in_correctness = 0
    next
  }

  # Process checklist items inside the Correctness section
  in_correctness && /^[[:space:]]*-[[:space:]]\[ \]/ {
    total++
    item = tolower($0)

    is_mech = 0

    # Pattern checks (substring via index)
    if (index(item, "grep")         > 0) is_mech = 1
    if (index(item, "jq ")         > 0 || item ~ /[^a-z]jq$/ || item ~ /[^a-z]jq[^a-z]/) is_mech = 1
    if (index(item, "exit code")    > 0) is_mech = 1
    if (index(item, "exits 0")      > 0) is_mech = 1
    if (index(item, "file exists")  > 0) is_mech = 1
    if (index(item, "wc -l")        > 0) is_mech = 1
    if (index(item, "find ")        > 0) is_mech = 1
    if (index(item, "returns")      > 0 && (index(item, "≥") > 0 || index(item, ">=") > 0 || index(item, "at least") > 0)) is_mech = 1
    if (item ~ /bash.*\.test\.sh.*exits/) is_mech = 1
    if (item ~ /\.test\.sh.*exits[ ]*0/)  is_mech = 1

    if (is_mech) mech++
  }

  END {
    if (total == 0) {
      printf "{\"mechanical_pct\":0,\"judgment_pct\":0,\"recommended_level\":\"system\"}\n"
      exit 0
    }

    mech_pct = int(mech * 100 / total + 0.5)
    judg_pct = 100 - mech_pct

    if (mech_pct >= 80) {
      level = "inline"
    } else if (mech_pct >= 40) {
      level = "unit"
    } else {
      level = "system"
    }

    printf "{\"mechanical_pct\":%d,\"judgment_pct\":%d,\"recommended_level\":\"%s\"}\n", \
      mech_pct, judg_pct, level
  }
' "$_PREREG_PATH"
