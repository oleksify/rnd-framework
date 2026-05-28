---
description: "Run the re-measurement pass against the M3 baseline: snapshots per-shape FAIL rate, builder-self-fail-vs-verdict gap, and iteration-depth distribution, then compares against the M3 recorded baseline and writes a memo to the active session dir. When fewer than 10 post-M5 dogfood sessions have accrued, writes a pending stub naming the current N. Requires duckdb on PATH; skips gracefully when absent."
effort: low
disallowed-tools: ["Edit", "Write"]
---

# R&D Framework: Re-measurement

> **DuckDB runs ONLY here, invoked by the user.** It is never called from the
> pipeline hot path (hooks, agents, or background scripts).

## 1. Probe for duckdb

```bash
if ! command -v duckdb > /dev/null 2>&1; then
  echo "rnd-remeasure: duckdb not found on PATH — skipping. Install duckdb to run the re-measurement pass."
  exit 0
fi
```

## 2. Resolve the session dir and the M5 ship commit

The memo is written to the active session's `$RND_DIR`. `M5_SHA` marks the
corpus boundary — sessions after this commit are "post-M5" and count toward
the N≥10 gate. Both may be pre-set by the caller (e.g. during testing); fall
back to canonical resolution otherwise.

```bash
if [[ -z "${RND_DIR:-}" ]]; then
  RND_DIR="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")"
fi

M5_SHA="${M5_SHA:-941cea0}"
```

## 3. Invoke the harness and write the memo

The harness (`lib/remeasurement.sh`) handles the corpus gate:
- When N < 10, writes a pending stub naming N and the threshold.
- When N ≥ 10, queries the existing DuckDB views and writes the full memo.

```bash
MEMO_PATH="${RND_DIR}/remeasurement-memo.md"

bash "${CLAUDE_PLUGIN_ROOT}/lib/remeasurement.sh" memo "$MEMO_PATH" "$M5_SHA"
```

## 4. Surface the memo

```bash
echo ""
echo "=== Re-measurement memo written to: ${MEMO_PATH} ==="
echo ""
cat "$MEMO_PATH"
```
