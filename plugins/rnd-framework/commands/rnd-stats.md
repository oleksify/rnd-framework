---
description: "Print the Phase 0 exit-criteria report: per-shape FAIL rate, builder-self-fail-vs-verdict gap, iteration depth, drift, and shape distribution — each segment-aware (dogfood vs feature). Requires duckdb on PATH; skips gracefully when absent."
effort: low
disallowed-tools: ["Edit", "Write"]
---

# R&D Framework: Stats

> **DuckDB runs ONLY here, invoked by the user.** It is never called from the
> pipeline hot path (hooks, agents, or background scripts). The views in
> `lib/stats/` are inert SQL until this command runs them.

## 1. Probe for duckdb

```bash
if ! command -v duckdb > /dev/null 2>&1; then
  echo "rnd-stats: duckdb not found on PATH — skipping. Install duckdb to view calibration stats."
  exit 0
fi
```

## 2. Resolve the .rnd root

Every view runs from the `.rnd` root — the directory whose immediate children
are the per-project slug dirs. Each slug dir holds its own `calibration.jsonl`
(`<slug>/calibration.jsonl`) and its sessions under either the legacy layout
(`<slug>/sessions/<id>/audit.jsonl`) or the current branch-partitioned layout
(`<slug>/branches/<branch>/sessions/<id>/audit.jsonl`). The audit views glob
`*/**/audit.jsonl` and the calibration views glob `*/calibration.jsonl`, so both
resolve correctly only from the `.rnd` root.

`rnd-dir.sh --calibration` prints `<.rnd>/<slug>/calibration.jsonl`; one
`dirname` yields the slug root, a second yields the `.rnd` root:

```bash
calib_file=$("${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh" --calibration)
rnd_root=$(dirname "$(dirname "$calib_file")")
```

If no project under the `.rnd` root has a `calibration.jsonl` yet, there is no
verdict data to report. The calibration views read `*/calibration.jsonl`, which
hard-errors on a zero-file match — so guard before running anything. DuckDB's
`glob()` table function lists matches without parsing and returns empty rows
(rather than erroring) when nothing matches:

```bash
cd "$rnd_root"
has_calib=$(duckdb -noheader -list -c "SELECT count(*) FROM glob('*/calibration.jsonl')" 2>/dev/null)

if [[ "${has_calib:-0}" -eq 0 ]]; then
  echo "rnd-stats: no calibration data yet. Run a full pipeline wave to populate stats."
  exit 0
fi
```

## 3. Configure the dogfood allowlist

Every view segments rows into `dogfood` vs `feature` by checking whether the
source slug appears in `RND_DOGFOOD_SLUGS` (a comma-separated env var, read
directly inside each SQL view via `getenv()`). This is the single source of
truth — no SQL view carries a hardcoded slug. Default is the framework's own
project slug; downstream users can override with their own CSV or leave it
unset (everything classifies as `feature`).

```bash
export RND_DOGFOOD_SLUGS="${RND_DOGFOOD_SLUGS:-claude-130cb64f}"
```

## 4. Run the views and print the Phase 0 exit-criteria report

The working directory is already the `.rnd` root (from the guard above), so the
relative globs in the SQL views resolve:

```bash
stats_dir="${CLAUDE_PLUGIN_ROOT}/lib/stats"
```

Run each view and display output under its named report section. The five
sections together form the **Phase 0 exit-criteria report**:

### Section 1 — Per-shape FAIL rate

Which assertion shapes fail most often, by segment (dogfood vs feature).

```bash
echo "=== Per-shape FAIL rate ==="
duckdb -c ".read ${stats_dir}/per_shape_fail_rate.sql" \
       -c "SELECT segment, shape, task_count, fail_count, fail_rate FROM per_shape_fail_rate ORDER BY segment, shape"
```

### Section 2 — Builder-self-fail-vs-verdict gap

How often the builder's self-assessment disagrees with the verifier's verdict,
by segment. A non-zero gap_count is a calibration signal.

```bash
echo ""
echo "=== Builder-self-fail-vs-verdict gap ==="
duckdb -c ".read ${stats_dir}/self_fail_vs_verdict_gap.sql" \
       -c "SELECT segment, task_count, self_fail_count, verifier_fail_count, gap_count FROM self_fail_vs_verdict_gap ORDER BY segment"
```

### Section 3 — Iteration depth

Distribution of how many build-verify cycles tasks required, by segment. The
view tolerates two calibration-record shapes: a stored `iterationCount` field
(fixture/legacy) takes precedence; otherwise depth is derived as the count of
records up to and including the first PASS in chronological order. Records
after the first PASS are re-verifies, not new cycles, and are excluded.

```bash
echo ""
echo "=== Iteration depth ==="
duckdb -c ".read ${stats_dir}/iteration_depth.sql" \
       -c "SELECT segment, iteration_count, task_count FROM iteration_depth ORDER BY segment, iteration_count"
```

### Section 3a — Iteration reasons

Distribution of the non-PASS verdicts that triggered re-iterations, by
segment. Companion to Section 3: depth says *how many* cycles, reasons says
*why* they iterated.

```bash
echo ""
echo "=== Iteration reasons ==="
duckdb -c ".read ${stats_dir}/iteration_reasons.sql" \
       -c "SELECT segment, reason_verdict, occurrences FROM iteration_reasons ORDER BY segment, reason_verdict"
```

### Section 4 — Drift (FAIL rate over time)

Verifier-FAIL rate bucketed by ISO week, by segment. Rising rates signal
verification quality degradation.

```bash
echo ""
echo "=== Drift (FAIL rate over time) ==="
duckdb -c ".read ${stats_dir}/fail_rate_over_time.sql" \
       -c "SELECT segment, week, task_count, fail_count, fail_rate FROM fail_rate_over_time ORDER BY segment, week"
```

### Section 5 — Shape distribution

Count of emitted (session, assertion) facts per shape, by segment. Shows
which assertion shapes dominate the workload.

```bash
echo ""
echo "=== Shape distribution ==="
duckdb -c ".read ${stats_dir}/shape_distribution.sql" \
       -c "SELECT segment, shape, task_count FROM shape_distribution ORDER BY segment, shape"
```

### Section 6 — Sycophancy probe flip rate

Hard-flip rate of fresh adversarial re-reviews over historical PASS verdicts,
split by artifact basis. A hard flip is a re-review that returned FAIL or
NEEDS_ITERATION; a soft flip returned PASS_QUALITY_NEEDS_ITERATION. The
`pinned_commit` subset (artifact reconstructed at the original commit) is the
drift-free measurement; `head_fallback` is reported separately as a weaker basis.

**Static-artifact confound:** the raw `hard_flip_rate` over the full corpus
conflates two qualitatively different assertion kinds. Static-document assertions
(docs, config, prose) can be re-verified by re-reading the same artifact unchanged.
Execution or multi-file assertions (behaviour, data-transform, system-integration)
require re-running code or reconstructing state — the probe can only do a weaker
text read, so flips may reflect probe access-asymmetry rather than genuine
sycophantic softening. The `hard_flip_count`, `soft_flip_count`, and
`hard_flip_rate` shown here are computed ONLY over rows where
`statically_verifiable = 'true'` (set at ingest time), so all three measure the
same population. Rows lacking that flag — including the full historical corpus —
are counted in `not_statically_reverifiable_count` and are excluded from the
clean counts.

This section is populated by the one-shot probe harness
(`lib/sycophancy-probe.sh`), which writes `<slug>/sycophancy-probe.jsonl`. The
glob hard-errors on a zero-file match, so guard on its existence first — print a
pending line and skip when no probe has run, consistent with the no-calibration
guard above.

```bash
echo ""
echo "=== Sycophancy probe flip rate ==="
has_probe=$(duckdb -noheader -list -c "SELECT count(*) FROM glob('*/sycophancy-probe.jsonl')" 2>/dev/null)

if [[ "${has_probe:-0}" -eq 0 ]]; then
  echo "pending — no sycophancy probe data yet. Run lib/sycophancy-probe.sh to populate."
else
  duckdb -c ".read ${stats_dir}/sycophancy_flip_rate.sql" \
         -c "SELECT artifact_basis, record_count, hard_flip_count, soft_flip_count, hard_flip_rate, not_statically_reverifiable_count FROM sycophancy_flip_rate ORDER BY artifact_basis"
fi
```

### Section 7 — Drift watch

Rolling-window linear regression over per-session iteration load (`iter_metric`) and
replan frequency (`replan_count`), ordered by session ordinal within each segment.
Slopes are computed over a 10-session window (`window_n`); a full window requires
exactly 10 sessions (`window_n = 10`). Falling `iter_slope` and `replan_slope` over
time indicate the pipeline is converging — tasks and waves are clearing with fewer
cycles. The signal to watch for is a divergence: `iter_slope` and `replan_slope`
falling (or holding near zero) while the quality signal in Section 1 (per-shape FAIL
rate) and Section 4 (FAIL-rate drift) does NOT improve in proportion — that pattern
is the success-induced verifier-softening signal, where the verifier grades more
leniently as familiarity grows rather than because the work genuinely improved.

The audit glob (`*/**/audit.jsonl`) hard-errors on a zero-file match — guard its
existence before invoking the view, mirroring the Section 6 probe guard.

```bash
echo ""
echo "=== Drift watch ==="
has_audit=$(duckdb -noheader -list -c "SELECT count(*) FROM glob('*/**/audit.jsonl')" 2>/dev/null)

if [[ "${has_audit:-0}" -eq 0 ]]; then
  echo "pending — N=0"
else
  max_window=$(duckdb -noheader -list \
    -c ".read ${stats_dir}/drift_watch.sql" \
    -c "SELECT COALESCE(MAX(window_n), 0) FROM drift_watch" \
    2>/dev/null)
  if [[ "${max_window:-0}" -lt 10 ]]; then
    echo "pending — N=${max_window:-0}"
  else
    duckdb -c ".read ${stats_dir}/drift_watch.sql" \
           -c "SELECT segment, session_ordinal, session_id, iter_metric, replan_count, iter_slope, replan_slope, window_n FROM drift_watch ORDER BY segment, session_ordinal"
  fi
fi
```
