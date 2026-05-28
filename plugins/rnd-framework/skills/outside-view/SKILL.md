---
name: outside-view
description: "Use in Phase 1 of rnd-start (after the premortem fan-out, before the Planner spawn) to inject a historical reference-class block — per-shape FAIL rates from the session corpus — into the Planner's context as a calibration anchor."
effort: low
user-invocable: false
---

# Outside View

A reference-class injection mechanism that runs DuckDB stats over the historical session corpus, formats per-shape FAIL rates into a markdown block, and injects that block into the Planner spawn prompt during Phase 1 of `rnd-start`. The block is read by the Planner before any estimation so the Planner sees historical base rates first.

## Overview

The outside-view mechanism fires once per `rnd-start` session, in the Phase 1 pre-step that runs AFTER the premortem fan-out and BEFORE the Planner spawn. It has no user-visible trigger — it is wired automatically into the orchestrator flow.

When invoked, `lib/outside-view.sh` queries `lib/stats/per_shape_fail_rate.sql` against the historical `.rnd` corpus, formats the results into a `## Outside View (Reference Class)` markdown block, writes that block to `$RND_DIR/outside-view.md`, and emits it on stdout so the orchestrator can capture it as `$OUTSIDE_VIEW_BLOCK`. The block is then appended to the Planner spawn prompt.

`lib/outside-view-emit.sh` appends one `outside_view_injected` audit event to `$RND_DIR/audit.jsonl` after the block is rendered.

## Block format

The rendered block has three parts in this order:

1. A header line: `## Outside View (Reference Class)`
2. A `## Framing constraint` section (always present, even in thin-corpus and unavailable modes).
3. An `- n_total: <int>` line followed by a `- Mode: ready | thin-corpus | unavailable` line, then either per-shape rows (ready mode only) or nothing (thin-corpus / unavailable).

Per-shape rows are bulleted, one shape per line:

```
- Shape: <shape>  segment=<segment>  task_count=<int>  fail_count=<int>  fail_rate=<float>
```

In thin-corpus or unavailable mode, per-shape rows are suppressed; only the `n_total` and `Mode` lines (plus `- dropped_rows: <int>` if any CSV rows were malformed) follow the framing section.

## Thin-corpus operational definition

When `n_total < 5`, the injector fires in thin-corpus mode: per-shape `fail_rate` numbers are suppressed and the block emits `Mode: thin-corpus` instead. `n_total` is the total count of verifier verdicts in the `dogfood` segment after DuckDB view aggregation, regardless of shape distribution. The threshold value `5` is declared as `N_THIN_CORPUS=5` in `lib/outside-view.sh`.

## Framing constraint

Shape base rate is a calibration anchor, NOT a license to pack more assertions
and NOT a trigger for theater-decomposition. If a shape's historical FAIL rate
is low, that is evidence the rate is well-tracked for similar shapes — it is
NOT permission to compress decomposition. If a shape's historical FAIL rate
is high, that is a warning to think carefully about decomposition — it is NOT
a mandate to shatter the task into micro-assertions.

## When the injector is invoked

The injector is a Phase 1 pre-step in `commands/rnd-start.md`:

1. Premortem fan-out runs (N parallel `rnd-premortem-imaginer` spawns).
2. **Outside-view injection runs** — `lib/outside-view.sh` queries the corpus and renders the block; `lib/outside-view-emit.sh` appends the audit event.
3. Planner spawn runs with `$OUTSIDE_VIEW_BLOCK` appended to the prompt.

The injector is NOT wired into `commands/rnd-resume.md` because resume does not have a planning phase.

## Audit event

After the block is rendered, `lib/outside-view-emit.sh` appends one line to `$RND_DIR/audit.jsonl` with this shape:

```json
{
  "event": "outside_view_injected",
  "mode": "thin-corpus" | "ready" | "unavailable",
  "n_total": <integer>,
  "shapes": [
    {"shape": "<shape>", "task_count": <int>, "fail_count": <int>, "fail_rate": <float>}
  ],
  "framing_constraint_emitted": <bool>,
  "timestamp": "<ISO-8601Z>"
}
```

`mode: "ready"` — `n_total >= 5`, per-shape rows present.
`mode: "thin-corpus"` — corpus below the thin-corpus threshold, per-shape rows suppressed.
`mode: "unavailable"` — `duckdb` absent or query failed; `shapes` is `[]`, `n_total` is `0`.
`framing_constraint_emitted` is `true` when the rendered block contains the `## Framing constraint` section.
