# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing **rnd-framework** — a scientific-method orchestration system for structured coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition. Uses a multi-agent execution model: 12 specialized agents (9 pipeline-phase + 3 helpers) with structural isolation enforce the information barrier at the context-window level.

The plugin lives under `plugins/rnd-framework/`. The root `.claude-plugin/marketplace.json` is a local plugin registry. Plugins can also be declared inline in `settings.json` using `source: 'settings'` (v2.1.80+).

## Repository Layout

```
lib/plugin-dir-base.sh                  # Canonical shared artifact-dir logic (each plugin keeps its own copy for cache compat)

plugins/rnd-framework/
├── .claude-plugin/plugin.json          # Plugin manifest
├── agents/                             # 12 agents (9 pipeline-phase + 3 helpers: premortem fan-out + replan-differ + assertion paraphraser)
├── commands/                           # /rnd-framework:* slash commands
├── skills/                             # One dir per skill, each with SKILL.md
├── output-styles/                      # scientific, rigorous, pipeline
├── hooks/
│   ├── hooks.json                      # Routes Session/Setup/InstructionsLoaded/Pre+PostToolUse/Pre+PostCompact/StopFailure/Cwd+FileChanged/TaskCreated/Subagent*/PermissionDenied/Worktree*
│   ├── lib.sh                          # Shared bash utils: input parsing, path predicates, decision output (incl. defer), cmd_hash; path-identity helpers (session_id_from_path, calib_path_from_artifact, parse_contract_assertions, normalize_artifact_path) shared by the stat producers
│   ├── read-gate.sh / write-gate.sh / glob-grep-gate.sh / bash-gate.sh   # Info barrier + tool discipline + .rnd/ auto-allow
│   ├── session-start.sh / session-end.sh / pre-compact.sh / post-compact.sh
│   ├── post-dispatch.sh                # Write/Edit audit + Bash output cache writer + ≥50-line advisory
│   ├── stop-failure.sh / setup.sh / instructions-loaded.sh / permission-denied.sh
│   ├── cwd-changed.sh / file-changed.sh / task-created.sh / subagent-lifecycle.sh
│   ├── format-on-save.sh / session-title.sh
│   ├── builder-dismissal-gate.sh / coverage-gaps-gate.sh / anomaly-gate.sh / verifier-case-gate.sh / cleanup-bloat-gate.sh / planner-emit-gate.sh / verification-debt-gate.sh   # SubagentStop quality gates (agent-scoped)
│   ├── self-assessment-producer.sh / shape-producer.sh / calibration-producer.sh   # PostToolUse Write|Edit path-driven Phase 0 stat producers (identity read off the artifact file_path via lib.sh helpers, NEVER .current-session). self-assessment.md write→{event:builder_self_assessment,task_id,self_verdict}; validation-contract.md OR features.json write (both-present gated)→one {event:assertion_shape,task_id,assertion_id,shape} per assertion mapped to its owning task via features.json — both to the session audit.jsonl with snake_case task_id; wave-<N>-verdict-map.json write→per-task {taskId,verdict} (camelCase) collapsed via the Gate 3 rule to the slug-root calibration.jsonl. Non-blocking. (Replaced the old builder-self-assessment-emit.sh SubagentStop hook, which mis-resolved the session via .current-session and emitted 0 events.)
│   ├── evidence-pack-gate.sh           # PreToolUse Read: validates evidence-pack manifest schema for verifier
│   ├── evidence-locking-gate.sh        # PreToolUse Write|Edit, verifier-scoped. Blocks the verifier's wave-N-verdict-map.json write when any assertion entry has an empty, missing, or trivial (every-not-any) evidence array. Two-pass validation: (1) form pass via single jq walk rejects trivial evidence; (2) substance pass extracts a citable token from each form-passing item and confirms it appears in the union corpus (session dir + project repo root, excluding barrier dirs). One gate_fired event per blocked write (first offender).
│   └── statusline.sh                   # Rate-limit % + pipeline phase
├── lib/
│   ├── rnd-dir.sh                      # $RND_DIR resolver and session manager (flags: -c, --finish, --base, --roadmap, --facts, --calibration)
│   ├── plugin-dir-base.sh              # Local copy of shared artifact-dir logic
│   ├── bump.sh / validate.sh / validate-xrefs.sh
│   ├── tools.json                      # Heavy-tool registry (pytest/jest/vitest/tsc/eslint/dialyzer/mypy/bun/cargo/mix/ruff/biome) with relevant_globs for input scoping; project override at $RND_DIR/tools.json
│   ├── run-tool.sh                     # Evidence-pack writer (opt-in: RND_EVIDENCE_PACK=1)
│   ├── manifest-schema.json            # JSON Schema for evidence-pack manifest; `x-disallowed-fields` is the SSOT consumed by evidence-pack-gate.sh
│   ├── event-schema.json               # JSON Schema SSOT for the per-(session,assertion) fact grain; `x-shape-vocab` (13 values incl. `behaviour`, `misc`) + confidence enum (high|medium|stretch) sourced by planner-emit-gate.sh
│   ├── verdict-map-schema.json         # Canonical definition of the verifier verdict-map evidence-array shape (JSON Schema). Sourced at runtime by evidence-locking-gate.sh via jq — `x-trivial-tokens` (19-item denylist), `x-min-evidence-length` (40), `x-evidence-citation-markers` (5 markers), and `x-substance-exclude-dirs` (4 barrier dirs) live here.
│   ├── stats/*.sql                      # Stateless DuckDB view module over session JSONL in place (tolerant `read_csv` raw-line + `json_valid`, no persistence): shape distribution, per-shape verifier-FAIL rate, iteration depth, builder-self-fail-vs-verdict gap, FAIL-rate drift, sycophancy flip rate (over `*/sycophancy-probe.jsonl`, per-`artifact_basis` hard/soft split, with the clean hard-flip rate scoped to `statically_verifiable='true'` rows and execution/multi-file rows reclassified — never dropped — into a not-statically-re-verifiable bucket), drift watch (per-segment rolling 10-session regr_slope of iteration metric and replan frequency), + backfill.sql; segment via inline `dogfood_slugs` CTE; run out-of-band by /rnd-framework:rnd-stats (Section 6 = sycophancy, Section 7 = drift watch)
│   ├── remeasurement.sh                 # M7 re-measurement harness: subcommands `corpus_count <sha>` (counts dogfood session dirs newer than the M5 ship commit) and `gate_met <sha>` (exit 0 at N≥10, exit 1 below); `memo <out_path> <sha>` writes a pending stub when the gate is unmet or queries stats/per_shape_fail_rate + self_fail_vs_verdict_gap + iteration_depth and emits a markdown memo with M3-baseline-recall + current-snapshot + delta + M4+M5 confound disclosure + follow-up signals sections. Read-only over the existing M1 substrate; invoked by /rnd-framework:rnd-remeasure.
│   ├── audit-event.sh                  # Single-line {event,task_id,tool,timestamp} emitter to $RND_DIR/audit.jsonl
│   ├── premortem-emit.sh               # Emits the premortem_generated event {event,n,framings[],failure_mode_count,timestamp}; n derived from the framings CSV (separate from audit-event.sh because the payload schema differs)
│   ├── outside-view.sh                 # Outside-view injector: queries stats/per_shape_fail_rate via duckdb, applies the N_THIN_CORPUS=5 gate, renders the `## Outside View (Reference Class)` block (header + framing-constraint paragraph + per-shape rows when n_total≥5, or `Mode: thin-corpus`/`Mode: unavailable` sentinels otherwise), writes $RND_DIR/outside-view.md and stdout. Invoked from commands/rnd-start.md Phase 1 between premortem fan-out and Planner spawn.
│   ├── outside-view-emit.sh            # Emits the outside_view_injected event {event,mode,n_total,shapes,framing_constraint_emitted,timestamp}; separate from audit-event.sh because the payload schema differs (mirrors the premortem-emit.sh pattern)
│   ├── paraphrase-emit.sh              # Appends a paraphrase_injected event {event,n_assertions,timestamp} to $RND_DIR/audit.jsonl; exits 1 on missing RND_DIR, missing arg, or non-integer arg; invoked consumption-gated in rnd-start.md Phase 3 (only after the paraphrased blocks have been inlined into the Verifier prompt)
│   ├── replan-emit.sh                  # Re-plan lifecycle emitter: subcommands `started <iteration> <archive_path>` → replan_started event; `diff_emitted <task_changes_count> <assertion_changes_count>` → replan_diff_emitted event; both append to $RND_DIR/audit.jsonl
│   ├── replan-archive.sh               # Re-plan archive helper: moves the four canonical plan artifacts (protocol.md, validation-contract.md, features.json, AGENTS.md) into $RND_DIR/prior-plans/replan-<k>/ where <k> is the next-available counter; prints archive path on stdout. Invoked by commands/rnd-start.md Phase 5 re-plan flow before the fresh Planner spawn.
│   ├── audit-scan.sh                   # Subcommands: `verdict_history <task>` (prints FLIP_DETECTED on PASS/FAIL/PASS or FAIL/PASS/FAIL)
│   ├── rnd-undo.sh                     # Surgical task-scoped revert (reads `## Files written` from build manifest)
│   ├── run-properties.sh               # Property-runner dispatcher: invokes `mix test --include property` (Elixir/StreamData) or `bun test` (TS/fast-check); emits `PROPERTY_PASS`, `PROPERTY_COUNTER_EXAMPLE` (stderr JSON: property/input/shrunk_input/seed), or `PROPERTY_SKIPPED`; probe via `command -v mix`/`bun` — absent runtime → skip; called by Verifier when pre-reg has `## Properties`
│   ├── sycophancy-probe.sh             # One-shot sycophancy-delta probe harness: `prepare` reconstructs each historical PASS assertion's artifact at its owning session's commit via guarded `git show` (artifact_basis pinned_commit|head_fallback), writing barrier-clean review-inputs (assertion text + artifact only); `ingest` appends a `{assertion_ref,session_id,commit_sha,artifact_basis,new_verdict,hard_flip,soft_flip,rationale,statically_verifiable}` record per fresh re-review to the slug-root `sycophancy-probe.jsonl` (`rationale` is the re-reviewer's free-text reasoning, default `""`; `statically_verifiable` is `"true"|"false"|null` and drives the stats segmentation — both backfill-safe, NULL/empty for the historical corpus); `summary` prints corpus/reviewed/dropped + pinned/fallback split. Orchestrator-driven, never in the hot path
│   └── calibration.sh                  # Auto-escalation helpers; subcommands: window, false_pass_rate, should_promote, promote_tier, task_type_window
└── README.md
```

## Architecture

### Execution Model

Twelve specialized agents (9 pipeline-phase + 3 helpers) handle pipeline work in isolated context windows. The orchestrator dispatches work to agents, enforcing structural information barriers — the Verifier literally cannot see the Builder's reasoning because they run in separate context windows.

| Phase | Agent | Purpose |
|---|---|---|
| Planning | `rnd-planner` (opus/high, adaptive) | Decomposes tasks and emits four artifacts: `protocol.md` (scope + goals; carries `Heuristic ceiling: <integer>` on line 2 for the plan-size stop condition), `validation-contract.md` (one `M<N>.<area>.<slug>` heading per testable assertion), `features.json` (task manifest with `M<N>.T<NN>.<slug>` IDs, `dependsOn[]`, `assertionIds[]`, `criticality`, `status`), and `AGENTS.md` (per-agent work assignments); capped at max 4 tasks/wave with min 1-hour scope and forced coalescing; pre-registrations include a required `## Assumptions` section (`Assumption: ... Refuted by: ...`, placeholder `- None` when none) — the Verifier downgrades a verdict by one tier and emits `gateFired: {gate: "assumption_unchecked"}` when an Assumption's Refuted-by action was declared but not executed |
| Building | `rnd-builder` (sonnet/high, adaptive) | Implements tasks using TDD; produces build manifest + self-assessment |
| Reality Audit | `rnd-reality-auditor` (sonnet/low) | Per-task audit of declared external references (URLs, APIs, schemas, env vars, data); only runs when the task declares `External dependencies`; runs an "Existence Pre-Pass" Step 0 (mechanical probes — file-execution only, no `python -c`/`node -e`/`bun -e`) that verifies every imported module / third-party method call / RFC or error-code citation / env-var name actually exists in the form claimed, before adversarial experiments; MISSING short-circuits to `INVALID_FOUND` and emits a `FALSE_PASS_PROXY` calibration record if a prior Builder PASS exists for the task |
| Verification | `rnd-verifier` (sonnet/high, adaptive) | Wave-batched: one spawn per wave reviews all task pre-regs and emits a **per-assertion verdict map** (`wave-<N>-verdict-map.json`) keyed by assertion ID, each entry carrying `{verdict, evidence[], feedback, task_id}`; Gate 3 aggregates per-task using the rule: any FAIL → NEEDS_ITERATION; any PASS_QUALITY_NEEDS_ITERATION without FAIL → PASS_QUALITY_NEEDS_ITERATION; all PASS → PASS; writes `T<id>-verification.md` full prose report for every verdict with a required `## Coverage Gaps` section (`Checked:` + `Couldn't check:` sub-bullets — enforced by `coverage-gaps-gate.sh`) and required `## Case for PASS` / `## Case for FAIL` sections (enforced by `verifier-case-gate.sh`); information barrier enforced |
| Cleanup | `rnd-cleanup` (sonnet/medium) | Per-task dead-code sweep after Verifier PASS; detects dead functions, orphan files, duplicate implementations, stale comments; applies fixes and rolls back if cleanup breaks re-verification |
| Polish | `rnd-polisher` (opus/high, non-adaptive, per-wave) | Wave-level cross-task seam fixer: detects cross-task duplication, naming and API drift, helpers that should be lifted to shared locations, and structural inconsistencies; runs after all per-task cleanup; rolls back if re-verification breaks; reports to `$RND_DIR/polish/wave-<N>-polish-report.md` |
| Integration | `rnd-integrator` (haiku/low) | Merges verified outputs, runs integration/system tests |
| Debugging | `rnd-debugger` (sonnet/high, adaptive) | Root cause analysis for failing tasks |
| Data Science | `rnd-data-scientist` (sonnet/medium) | Standalone specialist for numerical/analytical work |

**Dispatch Policy (criticality-driven, per-agent):** the orchestrator overrides the spawned agent's model based on the per-task `Criticality` field. The mapping is per-agent, not a single global table:

| Agent | LOW | NORMAL | HIGH |
|---|---|---|---|
| `rnd-planner` | opus/high | opus/high | opus/xhigh |
| `rnd-verifier` | sonnet/high | opus/high | opus/xhigh |
| `rnd-builder` | sonnet/high | sonnet/high | opus/high |
| `rnd-debugger` | sonnet/high | sonnet/high | opus/high |
| `rnd-polisher` (non-adaptive, per-wave) | opus/high | opus/high | opus/xhigh |

If `Criticality` is absent (or no pre-reg exists), the orchestrator does NOT override and the agent's frontmatter `model:` is used. Effort is NOT per-spawn overridable; it stays at the agent's frontmatter value. Non-adaptive agents always run at their listed model regardless of criticality. Full policy lives in the `rnd-framework:rnd-orchestration` skill.

### Information Barrier and Permission Hooks

The `hooks.json` routes each event to an external script under `hooks/`. The load-bearing policies:

- **Information barrier** (`read-gate.sh`, `glob-grep-gate.sh`, `bash-gate.sh`): blocks any tool call where the path or command string contains `self-assessment.md` (the builder uncertainty artifact) or `self-assessment-properties` (the property-runner output), OR matches `.rnd/.*briefs/`, OR matches `.rnd/.*cleanup/` — when the agent is `rnd-verifier` or `rnd-polisher`. The `self-assessment` patterns are matched on their artifact-specific tokens, NOT the bare `self-assessment` substring, so legitimately-named source files (e.g. `hooks/self-assessment-producer.sh` and its test) are not false-positives. The orchestrator (empty `agent_type`) is the legitimate consumer of briefs/ and self-assessment artifacts — it relays them to the user per the orchestration protocol and is NOT barrier-restricted. The `.rnd/` artifact-root anchor on the `/briefs/` and `/cleanup/` patterns is load-bearing: it distinguishes genuine artifact-tree paths from same-named directories in project source. Prevents verification phases from anchoring on build- or cleanup-phase reasoning. `glob-grep-gate.sh` additionally checks the concatenation of `path` + `pattern` so a split like `path=/.../.rnd/sessions/x` + `pattern=/cleanup/*.md` cannot smuggle a barrier-protected glob through.
- **Auto-allow `.rnd/` and plugin cache** (`read-gate.sh`, `write-gate.sh`, `bash-gate.sh`, `glob-grep-gate.sh`, `settings.json`): Read/Write/Edit/Glob/Grep on `.rnd/` artifact paths auto-allowed. For Bash, `.rnd/` auto-allow fires after info-barrier and git-protection checks pass. `read-gate.sh` also auto-allows `plugins/cache/` (skills, agents) and `$CLAUDE_CONFIG_DIR/learnings/` (cross-session knowledge).
- **Bash gate** (`bash-gate.sh`): enforces the information barrier (blocks commands targeting `self-assessment.md`/`self-assessment-properties`, `briefs/`, or `cleanup/` paths for verifier/polisher); blocks destructive git ops (`git reset --hard`, `git checkout .`, `git clean -fd`, etc.) and `git add .rnd/` artifact pollution; emits an advisory on `git push` to main/master/production. Auto-allows `.rnd/` and plugin-lib paths. Includes a Bash output cache advisory (identical re-runs within TTL are pointed at cached output).
- **Audit + Bash output cache** (`post-dispatch.sh`): logs Write/Edit ops to `$RND_DIR/audit.jsonl`, advises when output >50 lines, and writes Bash stdout/stderr to `$session/.bash-cache/<sha>.txt` keyed by `cmd_hash` from `lib.sh`. PreToolUse Bash detects identical re-runs within `RND_BASH_CACHE_TTL_SECONDS` (default 600) and points at the cached file when the prior output was ≥10 lines. Non-blocking; cache auto-clears with session.
- **Stop conditions**: The verdict-flip and plan-size stop conditions are enforced at the orchestration-prompt level (gate names `stop_condition_verdict_flip`, `stop_condition_plan_size`), invoke `AskUserQuestion`, and emit `gateFired` audit events.
- **SubagentStop quality gates** (agent-scoped): blocking — `builder-dismissal-gate.sh` (phrases like `pre-existing`/`out of scope` blocked; the only legal dismissal path is a `T<id>-found-issues.jsonl` ledger entry with `decision:"escalated"`); `coverage-gaps-gate.sh` (verification.md must have substantive `## Coverage Gaps`); `verifier-case-gate.sh` (must have substantive `## Case for PASS` and `## Case for FAIL` — symmetry forces opposing-side articulation); `anomaly-gate.sh` (reality-report must have sourced `## Anomalies` OR substantive `## No-Finding Rationale` ≥200 chars); `planner-emit-gate.sh` (blocks the `rnd-planner` when any `validation-contract.md` assertion lacks a valid `Shape:` ∈ `event-schema.json` `x-shape-vocab` or `Confidence:` ∈ {high,medium,stretch}); `verification-debt-gate.sh` (blocks the `rnd-verifier` when its most-recent `T<id>-verification.md` carries a non-trivial `## Verification Debt` section alongside a bare `Overall Verdict: PASS` — enforcing that a verifier relying on a pre-reg-named quality gate it found unavailable downgrades to `PASS_QUALITY_NEEDS_ITERATION` and records the debt rather than emitting a bare PASS on substitute evidence; trigger is structural, not a tool-name substring, so a correctly-downgraded verdict does not fire it). Advisory-only — `cleanup-bloat-gate.sh` emits `bloat_aversion_underperform` when cleanup deletion ratio <15%. Every block emits a `gate_fired` (or `gateFired`) audit event.
- **Evidence pack gate** (`evidence-pack-gate.sh`): PreToolUse Read; runs the info-barrier check first, then — only for `rnd-verifier` reading `$RND_DIR/evidence/T*/manifest.json` — validates the manifest by `jq has()` against `lib/manifest-schema.json`'s `x-disallowed-fields` (default: `notes`, `summary`, `confidence`, `reasoning`, `explanation`). Blocks with `EVIDENCE PACK BARRIER` on any disallowed field.
- **Evidence locking gate** (`evidence-locking-gate.sh`): PreToolUse Write|Edit; scoped to `rnd-verifier` writing `$RND_DIR/verifications/wave-*-verdict-map.json`. Sources `x-trivial-tokens` / `x-min-evidence-length` / `x-evidence-citation-markers` / `x-substance-exclude-dirs` from `lib/verdict-map-schema.json` (hardcoded fallback if schema unreadable). Two passes: (1) form pass — one streaming jq walk; an evidence item is **non-trivial** when length ≥ 40 OR it contains any citation marker (`:` `/` `` ` `` `"` `<`) — trivial-tokens denylist applies only when neither structural test passes; every-not-any semantics; (2) substance pass — extracts a citable token from each form-passing item (longest backtick span, then longest double-quoted span, then longest `/`-containing word) and confirms it appears in the union corpus (session dir + project repo root, excluding `x-substance-exclude-dirs`); items with no extractable token are exempt. On offender in either pass, emits one `gate_fired` event (`tool: evidence_locking_gate`, `task_id: <first offender>`) then blocks with stderr naming the violation. Coexists additively with `write-gate.sh`'s `.rnd/` auto-allow.
- **Other** observability/UX hooks: `stop-failure.sh` (API-error logging), `permission-denied.sh` (auto-mode denial → `{retry: true}`), `cwd-changed.sh` (cross-repo warning), `file-changed.sh` (external `.rnd/` edit advisory), `task-created.sh`, `subagent-lifecycle.sh`, `format-on-save.sh` (auto-format code on Write/Edit; cached detection; skips `.rnd/` artifact paths), `session-title.sh` (dynamic `RND: <phase> | <project>` title for `/resume`; gated on an active pipeline session — when no session is active the `sessionTitle` field is omitted so Claude Code keeps its own auto-generated title rather than branding every session `RND: <project>`; `session-start.sh` applies the identical gate so title visibility matches context-block visibility).

#### Claude Code Version Notes

**Min recommended:** v2.1.139 (`hooks.json` exec form for `args: string[]`). `session-start.sh` warns via `claude --version` when below threshold.

**Key version-gated behaviors:**
- v2.1.77+: deny rules > hook allow > default prompt. **Workaround for deny rules covering `.rnd/`:** set `allowRead`/`allowWrite` sandbox settings (e.g. `["~/.claude/.rnd/**"]`) — these override deny.
- v2.1.89+: `allowRead`/`allowWrite` resolve symlinks; hook output >50K saves to disk with preview; `permission-denied.sh` works (auto-mode denial retry).
- v2.1.90+: required minimum for format-on-save (earlier failed Write/Edit with "File content has changed" when a PostToolUse hook rewrote the file); auto mode respects explicit user boundaries.
- v2.1.94+: default effort raised to `high`; output styles set `keep-coding-instructions: true` to preserve coding instructions across compaction.
- v2.1.97+: statusline `refreshInterval: 5` works; subagent cwd no longer leaks to parent; 429 backoff applied as minimum.
- v2.1.113+: `sandbox.network.deniedDomains` honored (plugin ships denylist for pastebin-style exfil hosts); 10-min subagent stall timeout; `find -exec`/`-delete` no longer auto-approved (bash-gate already blocks `find`).
- v2.1.118+: agent-scoped hooks fire on non-Stop events; `SendMessage` restores spawn-time cwd; `autoMode.allow` supports `$defaults` keyword.

**Spawn mode:** pipeline agents spawn with `mode: "acceptEdits"`. Empirically `mode: "auto"` denied project-file Edit/Write on 2.1.112 team-spawned subagents; Bash still routes through the auto-mode classifier.

**`file_path` handling:** tool schemas require absolute paths but hooks receive raw `tool_input`. `lib.sh` path-predicate matchers (`is_plugin_artifact_path`, `is_plugin_cache_path`, `is_learnings_path`) reject paths not starting with `/` — relative paths fall through to default permission prompt.

**Plugin settings defaults:** `settings.json` ships `showThinkingSummaries: true`, `showTurnDuration: true`, `spinnerTipsEnabled: false`, `statusLines.refreshInterval: 5`, and `autoMode.allow` with `$defaults` plus safe pipeline Bash invocations (`bun test:*`, `python -m pytest:*`, read-only `git`, `jq:*`, `ls:*`). User settings take precedence.

### `--bare` Mode

`claude --bare` skips all hooks. Consequences: information barrier not enforced, tool discipline not enforced, skills not injected. rnd-framework effectively does not work in `--bare` mode — that flag is for scripted `-p` invocations, not interactive pipelines.

### Skill System

Skills are directories under `skills/` with a `SKILL.md` carrying YAML frontmatter (`name`, `description`, `effort`). Claude Code's plugin system discovers skills by directory convention. The `effort` field overrides reasoning effort when invoked: `low` for reference/guidance, `medium` for procedural workflows. Commands also support `effort` frontmatter: `low` (read-only), `medium` (moderate), `high` (deep pipeline orchestration).

**Session-local skill injection.** The orchestrator reads `$RND_DIR/AGENTS.md` and `$RND_DIR/skills/*/SKILL.md` at spawn time, injects their content under `## Session Context` and `## Session Skills` sections in every Agent() call, and records a `skill_injected` audit event per injected session-local skill. This lets a pipeline carry session-specific guidance — custom agents, domain context, project-specific patterns — without modifying global plugin files.

Notable skills: `rnd-roadmapping` (roadmap.md format + milestone lifecycle), `rnd-learning` (auto-capture pipeline gotchas to `$CLAUDE_CONFIG_DIR/learnings/`), `rnd-formatting` (detect+run project formatter pre-commit).

**Property runner (`lib/run-properties.sh`):** the Verifier invokes this dispatcher when a pre-reg has a `## Properties` section. Three pre-reg shapes are supported: inline markdown bullets, a YAML block under `## Verification`, or a sibling file `T<id>-properties.{exs,ts}`. The runner exits 0 on `PROPERTY_PASS`, non-zero on `PROPERTY_COUNTER_EXAMPLE` (stderr: JSON with `property`/`input`/`shrunk_input`/`seed`), or 0 on `PROPERTY_SKIPPED` when the runtime is absent. Calibration records carry `verification_mode` ∈ `property | prose | schema | skipped`. On FAIL the shrunk reproducer is auto-pinned to `<project>/test/properties/T<id>-counterexample.<ext>` and a `property_pinned` audit event is emitted.

**Shadowing:** Personal skills in user's `.claude/skills/` override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

**Plugin freshness (v2.1.81+):** ref-tracked plugins re-clone on every load, so the cached version is always current. The mismatch warning from `session-start.sh` should be rare in modern setups.

### Session Bootstrap

`SessionStart` fires on `startup|resume|clear|compact` → `hooks/session-start.sh` injects the full `using-rnd-framework` skill reminder (with the active `RND_DIR`) **only when a pipeline session is active** (`active_session_dir` non-empty AND the dir exists on disk — the on-disk check guards a stale `.current-session`); otherwise it emits a one-line `<system-reminder>` stub pointing at `/rnd-framework:rnd-start`, so idle sessions pay minimal context. It writes the `.session-git-root`/`.active-base-dir` caches via `resolve_rnd_dir --base` (no per-session `sessions/<id>` dir is created at SessionStart; the first `/rnd-framework:rnd-start` creates it, after which resume/compact restore the full block) and emits a version warning if below v2.1.139.

`SessionEnd` fires on close/switch (including `/resume`) → `hooks/session-end.sh` calls `rnd-dir.sh --finish` to clear `.current-session`.

**Remote pipelines:** `--channels` (v2.1.81+) forwards permission prompts to the Claude mobile app — useful for headless pipeline runs.

### Runtime Artifacts

Artifacts live in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated slug; each pipeline run gets a unique session ID.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR`. Flags: `-c` (create session under current branch), `--finish` (clear session), `--base` (branch-scoped project base), `--roadmap` / `--facts` (branch-scoped, lazy-inherit from default branch on first access), `--calibration` (slug-root, un-partitioned). Branch is resolved at each invocation via `git symbolic-ref --short HEAD`; detached HEAD → `detached-<sha7>`; non-git → `no-git`; slashes preserved as nested dirs; `..` rejected.

```
~/.claude/.rnd/<basename>-<hash>/          # Project slug; un-partitioned at the top
├── .active-base-dir                       # Cache: active branch-scoped base dir (fast-path in lib.sh::active_session_dir)
├── calibration.jsonl                      # Verdict-accuracy tracking, project-wide. Records may include: task_type (refactor|new-feature|bugfix|docs|config|infra); gateFired {gate, outcome, task_id}; verification_mode (property|prose|skipped)
└── branches/<branch>/                     # Branch-scoped partition (slashes → nested dirs)
    ├── .current-session                   # Active session ID
    ├── .session-git-root                  # Git root that started the session (written by session-start, read by cwd-changed)
    ├── roadmap.md                         # Multi-session roadmap (lazy-inherited from default branch)
    ├── project-facts.md                   # Persistent project scan (lazy-inherited from default branch)
    └── sessions/<YYYYMMDD-HHMMSS-XXXX>/   # $RND_DIR (one per pipeline run)
        ├── premortem.md                   # Orchestrator-owned, immutable; written BEFORE protocol.md from N parallel rnd-premortem-imaginer failure-imagination spawns; one FM<k> per failure mode; Planner addresses/dismisses each in protocol.md's ## Premortem Responses
        ├── outside-view.md                # Orchestrator-owned; written by lib/outside-view.sh BEFORE the Planner spawn during Phase 1 (between premortem and Planner); the rendered `## Outside View (Reference Class)` block (framing-constraint section + per-shape rows or thin-corpus/unavailable sentinel) is injected into the Planner prompt via ${OUTSIDE_VIEW_BLOCK}; the post-emit step writes an outside_view_injected event with payload {mode, n_total, shapes, framing_constraint_emitted}
        ├── protocol.md                    # Scope + goals; carries Heuristic ceiling integer on line 2
        ├── validation-contract.md         # One M<N>.<area>.<slug> assertion per heading; orchestrator slices per-task sets via assertionIds[] in features.json
        ├── features.json                  # Machine-readable task manifest: M<N>.T<NN>.<slug> IDs, dependsOn[], assertionIds[], criticality, status
        ├── AGENTS.md                      # Per-agent work assignments; consumed by orchestrator spawn-prompt builder + session-local skill injection
        ├── diagnosis/T*-diagnosis.md      # Debugger root cause (debug pipeline only)
        ├── builds/T*-manifest.md          # Terse build records (structured bullets, no narrative)
        ├── builds/T*-self-assessment.md   # Builder uncertainties (blocked from Verifier)
        ├── builds/T*-found-issues.jsonl   # Per-task issue ledger ({issue, location, decision:"fixed"|"escalated", reason}) — enforced by builder-dismissal-gate
        ├── verifications/wave-*-verdict-map.json   # Per-assertion verdict map keyed by assertion ID; each entry {verdict, evidence[], feedback, task_id}
        ├── verifications/T*-verification.md        # Full prose verdict report (for every verdict)
        ├── verifications/T*-experiments/  # Verifier-written independent tests
        ├── verifications/T*-evidence/     # Per-VAL-assertion raw output
        ├── evidence/T<id>/                # Builder-side evidence packs (opt-in: RND_EVIDENCE_PACK=1) — manifest.json + tool stdout/stderr/structured.json
        ├── audit.jsonl                    # Shared audit log: Write/Edit events from post-dispatch; tool_run_fresh from run-tool.sh; tool_pack_served from Verifier; lifecycle events; gateFired records
        ├── integration/wave-*-report.md   # Integration results, SHIP/NO-SHIP
        ├── cleanup/T*-cleanup-report.md   # Cleanup reports (barrier-protected from Verifier)
        ├── polish/wave-*-polish-report.md # Polisher wave-level seam-fix reports
        ├── prior-plans/replan-<k>/        # Archived planner artifact snapshots (one dir per re-plan generation, written by lib/replan-archive.sh); differ Reads from here to produce replan-diff.md
        ├── replan-diff.md                 # rnd-replan-differ output; sections ## Task delta, ## Assertion delta, ## Summary
        ├── .replan-in-progress            # Marker file enabling hooks/lib.sh::is_replan_artifact_violation; orchestrator touches before fresh Planner spawn and removes after diff_emitted
        ├── briefs/                        # Barrier-protected Builder-reasoning artifacts (blocked from Verifier by hooks)
        │   ├── decisions.md               # Cross-phase judgment-call log (rejected alternatives)
        │   ├── plan-briefs.md             # Planner user-facing narrative
        │   ├── T<id>-briefs.md            # Per-task user-facing narrative (Builder/Debugger)
        │   └── wave-<N>-briefs.md         # Per-wave integration narrative
        └── iteration-log.md               # Build-verify cycle tracking
```

Since `$RND_DIR` is outside the project, no `.gitignore` entry is needed.

## Commands

Slash commands use the plugin namespace: `/rnd-framework:rnd-start`, `rnd-plan`, `rnd-build`, `rnd-verify`, `rnd-integrate`, `rnd-status`, `rnd-resume`, `rnd-history`, `rnd-validate`, `rnd-doctor`, `rnd-bump`, `rnd-review`, `rnd-audit`, `rnd-brainstorm`, `rnd-narrative`, `rnd-calibrate`, `rnd-debug`, `rnd-roadmap`, `rnd-scan`, `rnd-stats`, `rnd-remeasure`.

## Key Conventions

- **Skills use YAML frontmatter** — `name`, `description`, `effort` between `---` delimiters.
- **Commands are Markdown files** in `commands/` — filename becomes the command name.
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`.
- **Tests** — `tests/` contains bash tests for hooks and lib scripts; run with `tests/run-tests.sh` from `plugins/rnd-framework/`.
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools` skill), then bash scripts, then Python as last resort.
- **File creation** — always use `Write`/`Edit`, never bash heredocs (`cat > file << 'EOF'`).
- **Report surfacing** — the three output styles each carry a "Report Surfacing Protocol" requiring the orchestrator to print agent/skill report artifacts (plans, design specs, manifests, verdict maps, reality reports, diagnoses, integration reports, iteration log, audits, reviews, narratives, brainstorms) verbatim before any next-step prompt — same turn, including autonomous/loop mode. Excluded: self-assessments, found-issues ledgers, cleanup reports, project-facts, calibration, audit log.

## Working on This Codebase

Skills and commands are Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
