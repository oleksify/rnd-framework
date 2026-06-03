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

## 2. Resolve the session dir

The memo is written to `$RND_DIR`. When a pipeline session is active, that is the
session dir; otherwise it is the branch base dir (and the block below says so).

The corpus boundary (the M5 ship moment) is a fixed epoch baked into the harness —
no git lookup and no commit SHA, so it cannot drift when history is rewritten. The
harness also reports on the framework's own dogfood corpus regardless of the project
you run it from; this is a framework self-measurement, not a per-project report.

```bash
if [[ -z "${RND_DIR:-}" ]]; then
  RND_DIR="$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh")"
fi

case "$RND_DIR" in
  */sessions/*) : ;;  # active pipeline session
  *) echo "rnd-remeasure: no active pipeline session — writing the memo to the branch base dir ($RND_DIR). Start from within an rnd-start session to nest it under that session." ;;
esac
```

## 3. Invoke the harness and write the memo

The harness (`lib/remeasurement.sh`) handles the corpus gate:
- When N < 10, writes a pending stub naming N and the threshold.
- When N ≥ 10, queries the existing DuckDB views and writes the full memo.

```bash
MEMO_PATH="${RND_DIR}/remeasurement-memo.md"

bash "${CLAUDE_PLUGIN_ROOT}/lib/remeasurement.sh" memo "$MEMO_PATH"
```

## 4. Surface the memo

```bash
echo ""
echo "=== Re-measurement memo written to: ${MEMO_PATH} ==="
echo ""
cat "$MEMO_PATH"
```
