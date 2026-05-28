# Protocol: M4 — Outside-view injector for the Planner
Heuristic ceiling: 5

## Scope

**In scope.** Ship a single behavior change: an "outside-view" mechanism that runs DuckDB stats views over the historical session corpus, formats per-shape reference-class numbers into a markdown block, and injects that block into the Planner spawn prompt during `commands/rnd-start.md` Phase 1 — BEFORE the Planner estimates. The mechanism is additive: a new skill file, a new library script, a new audit-event emitter, a new pre-step in the Phase 1 wiring, a minimal additive note in `agents/rnd-planner.md`, tests, validate-clean, minor version bump, CHANGELOG entry.

**Explicitly out of scope.** No second intervention (those are M5). No re-measurement of the per-shape FAIL rate or sycophancy probe (M5/M6). No verifier-side changes (M6 parked). No new model tiers. No replacement of existing agents. No `general-purpose`-based fan-out. No modification of `lib/stats/*.sql` views (the injector consumes them as-is). No changes to producer hooks. No changes to `commands/rnd-resume.md` (it does not have a planning phase).

## Milestones

M4 is the only milestone in this session. It is the third intervention milestone in the framework's self-improvement campaign. It targets the inside-view planning fallacy at the source: the Planner sees its first historical-data reference class before any estimation.

Roadmap-locked: M4 is a Planner-side change (Branch C adapted from the roadmap), NOT a verifier change — M3 found 0 clear false-PASSes, so there is no evidence verifier hardening is warranted yet.

## Constraints

- **Additive only.** Nothing existing is replaced or removed. Removals or refactors of unrelated code are out of scope and must be deferred.
- **Information barrier preserved.** The outside-view block does not enter Verifier contexts; the orchestrator pre-step writes it before the Planner spawn only.
- **No `general-purpose` fan-out** — user memory `feedback_general_purpose_spawn_overflow`.
- **No hardcoded `~/.claude-personal` paths in plugin files** — user memory `feedback_no_hardcoded_paths`. Use `$CLAUDE_CONFIG_DIR` or resolve via `lib/rnd-dir.sh`.
- **No emoji in source files or CHANGELOG** — global personal CLAUDE.md.
- **Off-limits.** Producer hooks (`hooks/shape-producer.sh`, `hooks/calibration-producer.sh`, `hooks/self-assessment-producer.sh`). Stats views (`lib/stats/*.sql`). Existing tests for those slices.

## Task Tree

- **M4.T01.injector-script** — Write `lib/outside-view.sh`: runs DuckDB on `per_shape_fail_rate` view, validates rows, applies the `n_total < 5` thin-corpus gate, formats the rendered block (header + framing constraint section + per-shape rows or thin-corpus sentinel), writes to `$RND_DIR/outside-view.md` AND stdout. Includes graceful degradation when `duckdb` is absent or corpus is empty.
- **M4.T02.emit-helper** — Write `lib/outside-view-emit.sh`: dedicated audit emitter for the `outside_view_injected` event. Payload `{event, mode, n_total, shapes, framing_constraint_emitted, timestamp}`. Modeled on `lib/premortem-emit.sh` with the same RND_DIR guard and `2>/dev/null || true` write tolerance.
- **M4.T03.skill-doc** — Write `skills/outside-view/SKILL.md`: documents the mechanism (when it fires, what the block contains, the thin-corpus operational definition `n_total < 5`, the framing constraint that addresses FM6).
- **M4.T04.wire-and-planner** — Insert a new sub-section "### Phase 1 pre-step: Outside-view injection" into `commands/rnd-start.md` between the premortem section and the Planner spawn. Update the Planner spawn prompt to reference `${OUTSIDE_VIEW_BLOCK}`. Add a small additive paragraph to `agents/rnd-planner.md` instructing the Planner to use the block as a calibration anchor.
- **M4.T05.ship-bump-and-e2e** — Minor version bump (5.4.4 → 5.5.0) via `lib/bump.sh --minor`. Write the CHANGELOG entry with the four mandatory content items (threshold, framing, audit event, wiring location). Run `validate.sh` + `validate-xrefs.sh`. Run the full test suite. Exercise the end-to-end flow once in a sandboxed session.

## Environment Setup

- **Runtime:** bash (POSIX-portable, the plugin runs on macOS and Linux).
- **Required CLIs at test time:** `jq` (already a project dependency), `git`, `awk`, `grep`, `sed`.
- **Optional runtime dep:** `duckdb` — when absent, the injector degrades to `Mode: unavailable` and still emits the audit event. The plugin's existing `rnd-stats` command already follows this pattern.
- **Install commands:** none — bash scripts execute directly; `chmod +x` is the only setup step for new `lib/*.sh` files.
- **Working directory for tests:** plugin root at `/Users/oleksify/Developer/oleksify/claude/plugins/rnd-framework/`. Tests use `mktemp -d` for sandboxed RND_DIR.

## Infrastructure

**External services:**
- `duckdb` (local CLI) — invoked by `lib/outside-view.sh` to run `lib/stats/per_shape_fail_rate.sql`. No network. No auth. Returns CSV on stdout.
- Filesystem read of historical `.rnd/` corpus (under `~/.claude/.rnd/<slug>/`) — read-only, owned by the user. No writes to historical sessions.

**Off-limits:**
- `lib/stats/*.sql` view definitions (consumer, not author).
- `hooks/shape-producer.sh`, `hooks/calibration-producer.sh`, `hooks/self-assessment-producer.sh` (the producers that feed the views).
- Existing tests under `tests/` that cover slices outside M4 — do NOT modify; add new tests only.

## Testing Strategy

**Test framework:** bash bats-style tests under `plugins/rnd-framework/tests/`, harnessed by `tests/run-tests.sh`. Baseline test count: ~65 test files.

**Unit tests:**
- `bash tests/outside-view-emit.test.sh` — emitter helper JSON shape, RND_DIR guard, single-line append.
- `bash tests/outside-view-skill.test.sh` — skill file frontmatter, threshold sentence content-against-script, framing constraint section content.
- `bash tests/outside-view-query.test.sh` — injector against fixture corpus (renders block, duckdb-absent path, empty corpus path, thin-corpus gate, row validation with `duckdb` shim).
- `bash tests/outside-view-wiring.test.sh` — `commands/rnd-start.md` wiring (section presence, ordering, prompt-includes-block, invokes-both-scripts), CHANGELOG content-against-protocol, validate.sh+xrefs clean, e2e dry run.
- `bash tests/outside-view-planner.test.sh` — `agents/rnd-planner.md` mentions outside-view block, diff against pre-edit baseline shows additions only.

**Integration/live tests:**
- `bash tests/run-tests.sh` — runs the full plugin test suite; must remain green (no regressions in the 65 baseline files).

**User testing:**
- Start a fresh `/rnd-framework:rnd-start` session in any project. Confirm:
  1. After premortem fan-out, `$RND_DIR/outside-view.md` is written.
  2. `$RND_DIR/audit.jsonl` contains a line with `.event == "outside_view_injected"`.
  3. The Planner spawn prompt contains the rendered block.
  4. On the M3-only corpus, the block reads `Mode: thin-corpus` (NOT `Mode: ready`).
  5. The Planner's first decomposition output references the outside-view section visibly (either uses the data or notes the corpus is thin) — visible in `briefs/plan-briefs.md` or in the produced `protocol.md`.

## Worker Guidelines

### Boundaries
- **USE:**
  - `lib/stats/per_shape_fail_rate.sql` (read-only consumer; do NOT modify).
  - `lib/audit-event.sh` and `lib/premortem-emit.sh` (study as patterns; the outside-view emitter is a sibling).
  - `lib/rnd-dir.sh` (resolve `$RND_DIR` and the slug root; never hardcode `~/.claude/.rnd`).
  - `lib/stats/fixtures/` (deterministic corpus for query tests).
  - `tests/test-helpers.sh`, `tests/premortem-*.test.sh` (test patterns).
- **OFF-LIMITS:**
  - `lib/stats/*.sql` (do not modify view bodies).
  - Producer hooks (`hooks/*-producer.sh`).
  - `agents/rnd-builder.md`, `agents/rnd-verifier.md`, `agents/rnd-cleanup.md`, `agents/rnd-polisher.md`, `agents/rnd-debugger.md`, `agents/rnd-integrator.md`, `agents/rnd-reality-auditor.md`, `agents/rnd-data-scientist.md`, `agents/rnd-premortem-imaginer.md` — additive only to `agents/rnd-planner.md`; all other agent files untouched.
  - Existing test files (`tests/*.test.sh`) other than new outside-view files.
  - Personal `~/.claude-personal/` paths (never hardcode).

### Coding Conventions
- `set -euo pipefail` at the top of every new bash script.
- Use functions to separate concerns: a `query_duckdb()` function distinct from a `render_block()` function distinct from an `emit_audit()` function (the last lives in `lib/outside-view-emit.sh`).
- All writes to `$RND_DIR/audit.jsonl` use `2>/dev/null || true` so a write failure never aborts the pipeline.
- jq for all JSON construction (no manual string interpolation).
- Reject `RND_DIR` unset early with a clear stderr message + non-zero exit (mirrors `audit-event.sh` and `premortem-emit.sh`).
- Constants like `N_THIN_CORPUS=5` are declared exactly once at the top of `lib/outside-view.sh` so the skill and the runtime cannot drift.
- No emoji in source, tests, or CHANGELOG.

### Architecture
- The injector is a single concern: query the historical corpus, validate the data, render a calibrated block, write to disk, return stdout. It does NOT decide whether the Planner uses the block — that is the Planner's job, gated by the explicit instruction in `agents/rnd-planner.md`.
- The emitter is a separate concern: take the same data the injector computed and append one audit-event line. Two scripts because the responsibilities differ — mirrors `lib/premortem-emit.sh` separation from `lib/audit-event.sh`.
- The Phase 1 wiring is the third concern: invoke injector, invoke emitter, inject block into Planner spawn prompt. The wiring lives in `commands/rnd-start.md` only — `rnd-resume.md` does not get the wiring because it does not have a planning phase.

## Thin-corpus operational definition

`n_total < 5` triggers `Mode: thin-corpus`. This is the **single load-bearing operational constant** for FM5 (thin-corpus precision illusion):

- `n_total` = total verifier verdicts the corpus contains in the `dogfood` segment after view aggregation, regardless of shape distribution.
- `5` is chosen as a conservative threshold: the M3-only corpus produces ~4 verdicts (one per task). The injector must NOT show per-shape `fail_rate=0%` numbers when n=1 sample dominates the corpus.
- The threshold value `5` lives in exactly two places: `N_THIN_CORPUS=5` in `lib/outside-view.sh`, and the sentence `"n_total < 5"` in `skills/outside-view/SKILL.md` and `CHANGELOG.md` entry. The Verifier asserts these two referents match (content-against-SSOT verification, not bare keyword presence — per `feedback_doc_task_content_verification`).
- When thin-corpus mode fires, the rendered block contains the literal phrase `Mode: thin-corpus` and the per-shape rows are SUPPRESSED. The block still contains the `## Framing constraint` section.

## Framing constraint (the FM6 countermeasure)

The rendered block carries a top section that constrains how the Planner uses the numbers:

```
## Framing constraint
Shape base rate is a calibration anchor, NOT a license to pack more assertions
and NOT a trigger for theater-decomposition. If a shape's historical FAIL rate
is low, that is evidence the rate is well-tracked for similar shapes — it is
NOT permission to compress decomposition. If a shape's historical FAIL rate
is high, that is a warning to think carefully about decomposition — it is NOT
a mandate to shatter the task into micro-assertions.
```

This phrasing is the FM6 countermeasure. It is asserted to appear verbatim (the three-phrase signature `calibration anchor` + `not a license` + `not a trigger`) in both the skill file and the runtime-rendered block (assertion `M4.skill.documents-framing-constraint`).

## Audit event payload

The emitter writes ONE line to `$RND_DIR/audit.jsonl` with the shape:

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

- `mode: "ready"` means `n_total >= N_THIN_CORPUS` and per-shape numbers are present in `shapes`.
- `mode: "thin-corpus"` means `n_total < N_THIN_CORPUS` — `shapes` may be empty or limited.
- `mode: "unavailable"` means duckdb absent or view query failed — `shapes` is `[]`, `n_total` is `0`.
- `framing_constraint_emitted` is `true` iff the rendered block contains the `## Framing constraint` section (it should always be `true`; the field is a paranoia check that the block-rendering function did not silently drop the section).

## Dependency Matrix

| Task | Depends on | Blocks |
|---|---|---|
| M4.T01.injector-script | — | M4.T04 |
| M4.T02.emit-helper | — | M4.T04 |
| M4.T03.skill-doc | — | M4.T04 |
| M4.T04.wire-and-planner | M4.T01, M4.T02, M4.T03 | M4.T05 |
| M4.T05.ship-bump-and-e2e | M4.T04 | — |

## Execution Schedule

- **Wave 1 (parallel, 3 tasks):** M4.T01.injector-script, M4.T02.emit-helper, M4.T03.skill-doc. Independent files, independent test files, no shared state.
- **Wave 2 (sequential, 1 task):** M4.T04.wire-and-planner. Modifies `commands/rnd-start.md` and `agents/rnd-planner.md`; both files must be edited in one task to preserve order assertions.
- **Wave 3 (sequential, 1 task):** M4.T05.ship-bump-and-e2e. Bump, CHANGELOG, full validate, full test run, e2e dry run.

## Iteration Budgets

Default: 3 iterations per task at NORMAL criticality (per `rnd-iteration` skill). No task exception requested. If M4.T04 hits the budget, the most likely root cause is wiring drift in `commands/rnd-start.md` — the Verifier should pin the failing assertion to a specific line range and the Builder should re-edit narrowly.

## Premortem Responses

- **FM1 — wrong-external-service-assumption:** **Addressed** — assertion `M4.injector.row-validation` requires field-count and null-check validation on every CSV row consumed from DuckDB; malformed rows are dropped and counted in `dropped_rows:`. Assertion `M4.injector.duckdb-absent-degrades` requires `Mode: unavailable` when `duckdb` is missing. Assertion `M4.injector.empty-corpus-degrades` requires `Mode: thin-corpus` + `n_total: 0` on empty input. Together these foreclose the "silent garbage block" failure path.
- **FM2 — data-model-misfit:** **Addressed** — protocol.md explicitly names the data model used. The view's shape dimension is the 12-value `x-shape-vocab` assertion-shape, and that is what the rendered block surfaces. The framing constraint section (asserted by `M4.skill.documents-framing-constraint`) explicitly tells the Planner the numbers are per-assertion-shape, not per-task-shape, and gives the Planner the rule for how to USE them: as a calibration anchor against overconfidence, regardless of the unit-of-decomposition mismatch. The audit event payload includes the `shapes` array verbatim so any future audit-log scan reveals exactly what shape vocab was injected.
- **FM3 — performance-at-scale:** **Dismissed for M4 ship; flagged for M5+ revisit.** At M4 the corpus has 1 producer-fed session (M3) plus pre-producer legacy data. The DuckDB scan over `*/**/audit.jsonl` runs in well under 2 seconds on this corpus. The injector is invoked exactly ONCE per Planner spawn — not in a hot inner loop. A `time` measurement at the wiring level is a future M5 concern when the corpus grows toward 50+ sessions. The injector exits 0 on any DuckDB error (including timeout) and degrades to `Mode: unavailable`, so even if performance degrades in the future, the Planner spawn is not blocked.
- **FM4 — user-meant-something-different:** **Addressed** — `M4.planner.agent-prompt-mentions-outside-view` asserts the Planner agent prompt is amended with an explicit instruction to read and apply the block. The instruction names the block by its literal section heading (`## Outside View (Reference Class)`) and tells the Planner the framing rule ("calibration anchor"). The block is not decoration: the Planner agent file changes mean the Planner will reference the block in its produced protocol.md. The user-testing checklist in this protocol's Testing Strategy includes a manual check that the Planner's first run output references the section.
- **FM5 — thin-corpus-precision-illusion:** **Addressed** — the load-bearing operational definition (`n_total < 5`) is documented in protocol.md, asserted in `M4.injector.thin-corpus-gate`, asserted to appear in the skill (`M4.skill.documents-thin-corpus-threshold`), and asserted to appear with matching meaning in the CHANGELOG (`M4.changelog.entry-content-matches-protocol`). The injector suppresses per-shape `fail_rate=N%` rows when below the threshold and emits a `Mode: thin-corpus` sentinel instead. The audit event records `mode` so any retroactive scan reveals when the block was meaningful vs noisy.
- **FM6 — anchoring-backfire:** **Addressed** — the framing constraint section is a load-bearing artifact, asserted in both the skill (`M4.skill.documents-framing-constraint`) and the runtime-rendered block. Its phrasing explicitly forecloses both directions of the inverted-anchoring trap: "NOT a license to pack more assertions" and "NOT a trigger for theater-decomposition". The CHANGELOG body must mention this constraint (`M4.changelog.entry-content-matches-protocol`). The Planner agent prompt instruction asserted by `M4.planner.agent-prompt-mentions-outside-view` includes the phrase "calibration anchor" so the rule reaches the agent's working context.

## Pre-Registration Documents

### M4.T01.injector-script

```
Task ID: M4.T01.injector-script
Intent: Build the DuckDB-driven outside-view injector library that renders a calibrated reference-class block for the Planner spawn.
Approach: Create `lib/outside-view.sh` with three internal functions: query_duckdb (runs `lib/stats/per_shape_fail_rate.sql` from the resolved `.rnd` root, captures stdout, returns empty on duckdb-absent or non-zero exit), parse_rows (splits CSV, validates field count = 5, drops malformed rows with a counter), render_block (writes a `## Outside View (Reference Class)` block with header, framing-constraint section, n_total/Mode lines, per-shape rows when not thin-corpus). Top-level entrypoint resolves $RND_DIR, calls each function in turn, writes the block to both `$RND_DIR/outside-view.md` AND stdout. Define `N_THIN_CORPUS=5` exactly once at the script top.
Expected outputs: `plugins/rnd-framework/lib/outside-view.sh` (executable). The script writes `$RND_DIR/outside-view.md` and emits the block on stdout when invoked.
Criticality: NORMAL
Success criteria:
  Correctness:
  - [ ] Script exists at the canonical path and is executable (`M4.injector.script-exists`).
  - [ ] Against the bundled fixture corpus, the script renders a structured block with header, Mode, n_total, and at least one Shape row (`M4.injector.renders-fixture-block`).
  - [ ] When `duckdb` is not on PATH, the script exits 0 and emits `Mode: unavailable` (`M4.injector.duckdb-absent-degrades`).
  - [ ] Against an empty `.rnd` root, the script exits 0 and emits `Mode: thin-corpus` + `n_total: 0` (`M4.injector.empty-corpus-degrades`).
  - [ ] With a 4-verdict sandboxed corpus, the script emits `Mode: thin-corpus` and suppresses per-shape `fail_rate` numbers. `N_THIN_CORPUS=5` appears exactly once in the script (`M4.injector.thin-corpus-gate`).
  - [ ] When a stub `duckdb` shim returns a malformed row, the script drops it and records `dropped_rows: 1` (`M4.injector.row-validation`).
  Quality:
  - [ ] `set -euo pipefail` at top; functions named with snake_case; no inline `cat <<EOF` heredocs for block rendering (use `printf` or a render function).
  - [ ] No hardcoded `~/.claude` paths; use `lib/rnd-dir.sh` for resolution.
Verification level: unit
Dependencies: (none)
Preconditions:
  - `lib/stats/per_shape_fail_rate.sql` exists at the plugin root (Glob confirms; do not modify).
  - `lib/stats/fixtures/claude-130cb64f/` exists for use as the deterministic test corpus.
  - `lib/rnd-dir.sh` exists and resolves `--base` correctly.
External Dependencies:
  - system: duckdb (local CLI)
    contract: when present, runs the SQL view and returns CSV on stdout matching schema `(segment, shape, task_count, fail_count, fail_rate)`. When absent, the injector must degrade gracefully.
    verification: probe with `command -v duckdb`; on absence emit `Mode: unavailable`. Field-count validation on every row before formatting.
  - system: file
    contract: write `$RND_DIR/outside-view.md` (creating parent dirs); the file is non-empty after invocation.
    verification: `test -s "$RND_DIR/outside-view.md"` after the script runs.
Assumptions:
  - Assumption: `lib/stats/per_shape_fail_rate.sql` output schema is `(segment, shape, task_count, fail_count, fail_rate)` in that column order.
    Refuted by: Read `lib/stats/per_shape_fail_rate.sql` final SELECT clause and confirm column order before parsing.
  - Assumption: `duckdb -csv -noheader -c ".read <path>" -c "SELECT * FROM per_shape_fail_rate"` returns one row per (segment, shape) when invoked from the `.rnd` root.
    Refuted by: Run the command manually once against `lib/stats/fixtures/claude-130cb64f/` and confirm row shape; if shape differs (e.g., requires `-list`), adjust parser before writing tests.
fulfills: [M4.injector.script-exists, M4.injector.renders-fixture-block, M4.injector.duckdb-absent-degrades, M4.injector.empty-corpus-degrades, M4.injector.thin-corpus-gate, M4.injector.row-validation]
```

### M4.T02.emit-helper

```
Task ID: M4.T02.emit-helper
Intent: Build a dedicated audit-event emitter for the outside_view_injected event, mirroring the lib/premortem-emit.sh pattern for non-canonical payload shapes.
Approach: Create `lib/outside-view-emit.sh` with the same skeleton as `lib/premortem-emit.sh`: `set -euo pipefail`, require RND_DIR, accept positional args (`mode`, `n_total`, `shapes_json`, `framing_constraint_emitted`), build the JSON line with jq, append to `$RND_DIR/audit.jsonl` with `2>/dev/null || true`. Validate `n_total` as integer and `framing_constraint_emitted` as boolean via jq's `--argjson`.
Expected outputs: `plugins/rnd-framework/lib/outside-view-emit.sh` (executable).
Criticality: NORMAL
Success criteria:
  Correctness:
  - [ ] Script exists, is executable, and has a usage-line in a leading comment block (`M4.emit.helper-script-exists`).
  - [ ] Appended JSON line has the required schema; jq-checked field-by-field; ISO8601Z timestamp (`M4.emit.payload-schema`).
  - [ ] Missing RND_DIR causes non-zero exit and a stderr message naming RND_DIR (`M4.emit.no-rnd-dir-rejects`).
  Quality:
  - [ ] All JSON built via jq, never via raw printf interpolation.
  - [ ] Single-line append (use `>> "$RND_DIR/audit.jsonl"` with redirection error swallow).
Verification level: unit
Dependencies: (none)
Preconditions:
  - `lib/premortem-emit.sh` exists as a reference pattern.
  - `jq` is on PATH (project-wide dependency).
External Dependencies:
  - system: file
    contract: append-only write to `$RND_DIR/audit.jsonl` (one line per invocation; preserves existing lines).
    verification: `wc -l` before and after invocation; difference is exactly 1.
Assumptions:
  - Assumption: jq's `--argjson` correctly handles `n_total` as a number and `framing_constraint_emitted` as a boolean without quoting.
    Refuted by: Inspect `lib/premortem-emit.sh`'s use of `--argjson failure_mode_count` which is the same pattern.
  - None
fulfills: [M4.emit.helper-script-exists, M4.emit.payload-schema, M4.emit.no-rnd-dir-rejects]
```

### M4.T03.skill-doc

```
Task ID: M4.T03.skill-doc
Intent: Document the outside-view mechanism in a skill file the Planner reads at session-local injection time, including the load-bearing operational definitions for FM5 and FM6.
Approach: Create `skills/outside-view/SKILL.md` with YAML frontmatter (`name: outside-view`, `description: <one sentence>`, `effort: low`, `user-invocable: false`). Body sections: "## Overview" (what fires when), "## Block format" (header + framing-constraint + rows), "## Thin-corpus operational definition" (the `n_total < 5` rule, expressed as a complete sentence not a bare keyword), "## Framing constraint" (the verbatim three-phrase rule that the script also renders), "## When the injector is invoked" (Phase 1 pre-step, AFTER premortem, BEFORE Planner), "## Audit event" (the payload shape).
Expected outputs: `plugins/rnd-framework/skills/outside-view/SKILL.md`.
Criticality: NORMAL
Success criteria:
  Correctness:
  - [ ] Skill file exists with valid frontmatter (`M4.skill.file-exists-with-frontmatter`).
  - [ ] Threshold sentence `n_total < 5` appears exactly once, in a sentence (not just a bare token) (`M4.skill.documents-thin-corpus-threshold`).
  - [ ] `## Framing constraint` section contains the three-phrase rule (`calibration anchor` + `not a license` + `not a trigger`) (`M4.skill.documents-framing-constraint`).
  Quality:
  - [ ] Section headings use `## ` consistently; no emoji; markdown lints clean.
  - [ ] Frontmatter `description:` is at least 40 characters and explains when the skill fires.
Verification level: unit
Dependencies: (none)
Preconditions:
  - `skills/premortem/SKILL.md` exists as a reference pattern.
External Dependencies:
  - None
Assumptions:
  - Assumption: The Planner-agent injection of session-local skill bodies (`SESSION_SKILLS_FRAGMENT` mechanism in `commands/rnd-start.md`) is the path by which this skill reaches the Planner — separate from the runtime-rendered outside-view block.
    Refuted by: Re-read `commands/rnd-start.md` lines 41-75 to confirm the SESSION_SKILLS_FRAGMENT assembly; this skill is global (lives under `plugins/rnd-framework/skills/`, not under `$RND_DIR/skills/`), so it reaches the Planner via the standard plugin-skill discovery, not via the session-local mechanism. Confirm by reading `skills/premortem/SKILL.md`'s location.
fulfills: [M4.skill.file-exists-with-frontmatter, M4.skill.documents-thin-corpus-threshold, M4.skill.documents-framing-constraint]
```

### M4.T04.wire-and-planner

```
Task ID: M4.T04.wire-and-planner
Intent: Wire the outside-view injector into Phase 1 of commands/rnd-start.md between the premortem fan-out and the Planner spawn, and add an additive instruction to agents/rnd-planner.md telling the Planner how to consume the injected block.
Approach: Read `commands/rnd-start.md`. Locate the `### Phase 1 pre-step: Premortem fan-out` section end (the `---` separator at line 183) and the Planner spawn block (lines 185-194). Insert a new sub-section `### Phase 1 pre-step: Outside-view injection` between them with: (a) prose explaining the step, (b) a fenced bash block invoking `lib/outside-view.sh` to populate `$RND_DIR/outside-view.md` and capture the block as `$OUTSIDE_VIEW_BLOCK`, (c) a second fenced bash block invoking `lib/outside-view-emit.sh` after the block is rendered, (d) a `---` separator. Update the Planner spawn prompt at line 192 to include `${OUTSIDE_VIEW_BLOCK}` (or equivalent `$(cat ...)`) so the rendered block reaches the Planner. Read `agents/rnd-planner.md` and append a new paragraph (additive, not replacing existing content) instructing the Planner to read the `## Outside View (Reference Class)` block and treat it as a "calibration anchor, not a license".
Expected outputs: edits to `plugins/rnd-framework/commands/rnd-start.md` and `plugins/rnd-framework/agents/rnd-planner.md`. No other files modified.
Criticality: NORMAL
Success criteria:
  Correctness:
  - [ ] New section heading exists exactly once (`M4.wiring.outside-view-section-exists`).
  - [ ] Section ordering is premortem → outside-view → planner spawn (`M4.wiring.ordering-after-premortem-before-planner`).
  - [ ] Planner spawn prompt references `${OUTSIDE_VIEW_BLOCK}` or `cat .*outside-view` exactly once (`M4.wiring.planner-prompt-includes-block`).
  - [ ] Section invokes both `lib/outside-view.sh` and `lib/outside-view-emit.sh` in that order (`M4.wiring.invokes-injector-and-emitter`).
  - [ ] `agents/rnd-planner.md` contains `## Outside View (Reference Class)` and `calibration anchor` (or `not a license`); diff vs pre-edit baseline shows additions only (`M4.planner.agent-prompt-mentions-outside-view`).
  Quality:
  - [ ] No existing content in `commands/rnd-start.md` or `agents/rnd-planner.md` is deleted; this is purely additive.
  - [ ] The new section in `commands/rnd-start.md` follows the same prose-then-fenced-bash structure as the existing premortem section.
Verification level: integration
Dependencies: M4.T01.injector-script, M4.T02.emit-helper, M4.T03.skill-doc
Preconditions:
  - `lib/outside-view.sh` exists (M4.T01 complete).
  - `lib/outside-view-emit.sh` exists (M4.T02 complete).
  - `commands/rnd-start.md` line 183 still contains the `---` after the premortem section (verify via Read before editing).
  - `agents/rnd-planner.md` exists and is readable.
External Dependencies:
  - system: file
    contract: append/edit two project files; preserve all existing content.
    verification: line-count of `commands/rnd-start.md` STRICTLY increases (no deletions); line-count of `agents/rnd-planner.md` STRICTLY increases.
Assumptions:
  - Assumption: The Planner spawn block in `commands/rnd-start.md` has a single `prompt:` field at approximately line 192 that already concatenates `${SESSION_SKILLS_FRAGMENT}` at its end, and a similar concatenation is the right insertion point for `${OUTSIDE_VIEW_BLOCK}`.
    Refuted by: Re-read lines 185-194 of `commands/rnd-start.md` immediately before editing; confirm the prompt: line is the one to extend.
  - Assumption: `commands/rnd-resume.md` does NOT have a Planner spawn and therefore does NOT need outside-view wiring.
    Refuted by: Grep `commands/rnd-resume.md` for `rnd-planner` and `Planner` (case-insensitive); if any reference exists, escalate and stop — the wiring scope grows.
fulfills: [M4.wiring.outside-view-section-exists, M4.wiring.ordering-after-premortem-before-planner, M4.wiring.planner-prompt-includes-block, M4.wiring.invokes-injector-and-emitter, M4.planner.agent-prompt-mentions-outside-view]
```

### M4.T05.ship-bump-and-e2e

```
Task ID: M4.T05.ship-bump-and-e2e
Intent: Bump the plugin version to 5.5.0, write a CHANGELOG entry whose body content matches the protocol.md operational definitions, run validate.sh + validate-xrefs.sh, run the full test suite, and exercise the injector end-to-end once in a sandboxed session.
Approach: Compose the CHANGELOG body covering: thin-corpus threshold (`n_total < 5`), framing constraint (the `calibration anchor` + `not a license` phrases), audit event name (`outside_view_injected`), and wiring location (`Phase 1` and `rnd-start.md`). Invoke `lib/bump.sh --minor "Add outside-view injector for the Planner spawn" "<body>"`. Run `lib/validate.sh` and `lib/validate-xrefs.sh`. Run `tests/run-tests.sh`. Stage a fresh sandboxed `$RND_DIR` and invoke the new Phase 1 outside-view sub-section bash blocks directly; confirm `$RND_DIR/outside-view.md` is written and `$RND_DIR/audit.jsonl` contains the `outside_view_injected` event.
Expected outputs: `plugin.json` bumped to `5.5.0`. `CHANGELOG.md` new top entry. No other files modified.
Criticality: NORMAL
Success criteria:
  Correctness:
  - [ ] `plugin.json` `.version == "5.5.0"`; CHANGELOG top entry has matching `## 5.5.0 — ` and headline (`M4.changelog.entry-exists-with-version-bump`).
  - [ ] CHANGELOG top entry body contains all four mandatory content phrases (threshold, framing, audit event, wiring location) and each appears in protocol.md as well (`M4.changelog.entry-content-matches-protocol`).
  - [ ] End-to-end exercise emits `outside_view_injected` and writes a non-empty `$RND_DIR/outside-view.md` (`M4.e2e.full-pipeline-emits-event`).
  - [ ] `validate.sh` and `validate-xrefs.sh` exit 0 (`M4.e2e.validate-sh-and-xrefs-clean`).
  Quality:
  - [ ] CHANGELOG voice matches the existing 5.4.x entries (technical, short paragraphs, no marketing language).
  - [ ] `tests/run-tests.sh` regression: 65 baseline files plus the 4 new outside-view test files, all green.
Verification level: system
Dependencies: M4.T04.wire-and-planner
Preconditions:
  - All M4.T01-T04 artifacts exist.
  - `lib/bump.sh` runs cleanly from the plugin directory.
  - `lib/validate.sh` and `lib/validate-xrefs.sh` pass before the bump (no pre-existing failures the bump would mask).
External Dependencies:
  - system: file
    contract: edit `plugin.json` and `CHANGELOG.md`; stage both via `git add` (bump.sh does this).
    verification: `jq -r .version plugin.json` matches expected; `head -10 CHANGELOG.md` shows the new entry.
  - system: git
    contract: `git add` stages files but does NOT commit (commit is user-initiated).
    verification: `git status --porcelain` shows `M` for plugin.json and CHANGELOG.md after bump, no automatic commit.
Assumptions:
  - Assumption: `lib/bump.sh --minor` increments 5.4.4 → 5.5.0 (minor bump, patch resets to 0).
    Refuted by: Read `lib/bump.sh` semver-bump logic; confirm the `--minor` branch zero's the patch.
  - Assumption: All existing tests pass at HEAD before the M4 ship; no pre-existing red tests are being masked by the bump.
    Refuted by: Run `bash tests/run-tests.sh` once BEFORE any T01-T04 edits; record the baseline pass count; compare after.
fulfills: [M4.changelog.entry-exists-with-version-bump, M4.changelog.entry-content-matches-protocol, M4.e2e.full-pipeline-emits-event, M4.e2e.validate-sh-and-xrefs-clean]
```
