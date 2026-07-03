#!/usr/bin/env bash
# hooks/cleanup-bloat-gate.sh — SubagentStop hook.
# Advisory-only gate scoped to rnd-cleanup: observes the cleanup report's deletion
# ratio and emits a bloat_aversion_underperform audit event when the ratio is
# derivable and under the threshold, without blocking the agent.
# ALWAYS exits 0 — this gate never blocks.
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

set -euo pipefail

readonly BLOAT_THRESHOLD=15

raw="$(cat)"

agent_type="$(printf '%s' "$raw" | jq -r '.agent_type // ""' 2>/dev/null || true)"

agent_lower="$(_lower "$agent_type")"

if [[ "$agent_lower" != *"rnd-cleanup"* ]]; then
  exit 0
fi

session_dir="$(active_session_dir 2>/dev/null || true)"

if [[ -z "$session_dir" ]]; then
  exit 0
fi

# Locate the most recent cleanup report.
report_path=""
if compgen -G "${session_dir}/cleanup/T*-cleanup-report.md" > /dev/null 2>&1; then
  report_path="$(ls -t "${session_dir}/cleanup/"T*-cleanup-report.md 2>/dev/null | head -1)"
fi

if [[ -z "$report_path" || ! -f "$report_path" ]]; then
  exit 0
fi

# Extract task ID from filename: T1-cleanup-report.md → T1
report_base="${report_path##*/}"
task_id="${report_base%-cleanup-report.md}"

report_content="$(< "$report_path")"

# ---------------------------------------------------------------------------
# Ratio derivation — three-step fallback chain
# ---------------------------------------------------------------------------
#
# Step 1: explicit lines_removed: <int> field.
#   Denominator: total_touched: <int>, or sum of wc -l over files listed
#   under ## Mutations Applied.
# Step 2: Deletion ratio: <int> / <int> line.
# Step 3: exit 0 silently (ratio not derivable).
# ---------------------------------------------------------------------------

lines_removed=""
total_touched=""
ratio_pct=""

# --- Step 1: lines_removed: field ---

while IFS= read -r line; do
  if [[ "$line" =~ ^lines_removed:[[:space:]]*([0-9]+) ]]; then
    lines_removed="${BASH_REMATCH[1]}"
    break
  fi
done <<< "$report_content"

if [[ -n "$lines_removed" ]]; then

  # Try total_touched: field first.
  while IFS= read -r line; do
    if [[ "$line" =~ ^total_touched:[[:space:]]*([0-9]+) ]]; then
      total_touched="${BASH_REMATCH[1]}"
      break
    fi
  done <<< "$report_content"

  # If no total_touched, sum wc -l over files listed under ## Mutations Applied.
  if [[ -z "$total_touched" ]]; then
    in_mutations=0
    touched_sum=0

    while IFS= read -r line; do
      if [[ "$line" =~ ^##[[:space:]]Mutations[[:space:]]Applied ]]; then
        in_mutations=1
        continue
      fi

      if [[ "$in_mutations" -eq 1 ]]; then
        if [[ "$line" =~ ^## ]]; then
          break
        fi

        # Extract file paths from list items (lines starting with - or *)
        candidate=""
        if [[ "$line" =~ ^[[:space:]]*[-\*][[:space:]]+(.*) ]]; then
          candidate="${BASH_REMATCH[1]}"
          # Strip trailing metadata after a space (e.g. "path/to/file — remove dead fn")
          candidate="${candidate%% *}"
          candidate="${candidate%%	*}"
        fi

        if [[ -n "$candidate" && -f "$candidate" ]]; then
          file_lines="$(wc -l < "$candidate" 2>/dev/null || true)"
          if [[ -n "$file_lines" && "$file_lines" -gt 0 ]]; then
            touched_sum=$((touched_sum + file_lines))
          fi
        fi
      fi
    done <<< "$report_content"

    if [[ "$touched_sum" -gt 0 ]]; then
      total_touched="$touched_sum"
    fi
  fi

  # Compute ratio if denominator is available and non-zero.
  if [[ -n "$total_touched" && "$total_touched" -gt 0 ]]; then
    ratio_pct=$(( (lines_removed * 100) / total_touched ))
  fi

fi

# --- Step 2: Deletion ratio: <int> / <int> ---

if [[ -z "$ratio_pct" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ Deletion[[:space:]]ratio:[[:space:]]*([0-9]+)[[:space:]]*/[[:space:]]*([0-9]+) ]]; then
      del_num="${BASH_REMATCH[1]}"
      del_den="${BASH_REMATCH[2]}"
      if [[ "$del_den" -gt 0 ]]; then
        ratio_pct=$(( (del_num * 100) / del_den ))
      fi
      break
    fi
  done <<< "$report_content"
fi

# --- Step 3: ratio not derivable → silent exit 0 ---

if [[ -z "$ratio_pct" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Advisory: emit when ratio < threshold
# ---------------------------------------------------------------------------

if [[ "$ratio_pct" -lt "$BLOAT_THRESHOLD" ]]; then
  # This hook never sets RND_DIR; the active session is in session_dir (line 24).
  # audit-event.sh writes to $RND_DIR/audit.jsonl, so pass it explicitly.
  if [[ -n "$session_dir" ]]; then
    RND_DIR="$session_dir" bash "$(dirname "${BASH_SOURCE[0]}")/../lib/audit-event.sh" \
      "gate_fired" "$task_id" "bloat_aversion_underperform" 2>/dev/null || true
  fi

  printf 'cleanup-bloat-gate: %s deletion ratio %d%% is below the %d%% advisory floor — consider whether more code could be removed. Report path: %s\n' \
    "$task_id" "$ratio_pct" "$BLOAT_THRESHOLD" "$report_path" >&2
fi

exit 0
