# Changelog

## 3.26.0 — 2026-05-18

### Add refutation-first property verification with Elixir StreamData and TypeScript fast-check runners

**New runner:** `lib/run-properties.sh` dispatches property execution by language. Probes runtimes via `command -v mix` / `command -v bun`; emits `PROPERTY_PASS`, `PROPERTY_COUNTER_EXAMPLE` (stderr JSON: `property`, `shrunk_input`, `seed`), or `PROPERTY_SKIPPED` on absent runtime. Awk parsers tuned against real ExUnit/StreamData 1.3.0 and bun 1.3.14/fast-check 3.23.2 output. Schema-as-degenerate-property dispatch for the Reality Auditor (presence-of-keys check via single jq pass; malformed-fixture inputs fail-fast with exit 2, not a false PROPERTY_PASS).
**Pre-reg extension:** `## Properties` section in pre-regs supports three shapes — markdown bullets, embedded YAML under `## Verification`, or a sibling test file `T<id>-properties.{exs,ts}`. Documented in `rnd-decomposition` and `rnd-orchestration` skills; absence of the section means prose-mode verification as before.
**Verifier integration:** `rnd-verification` Step 3.5 detects `## Properties`, invokes the runner, embeds counter-example JSON in `T<id>-verification.md` on COUNTER_EXAMPLE, and emits `property_run` and `property_counterexample` audit events. Counter-examples are auto-pinned to `<project>/test/properties/T<id>-counterexample.{exs,ts}` and tagged with a `property_pinned` event; `disallowedTools: Edit` invariant preserved (Write to a new file path is the pin mechanism).
**Calibration:** New `verification_mode` field on verdict records — `property | prose | schema | skipped`. Orchestrator writes; existing helpers (`lib/calibration.sh window`) tolerate missing field via `// null` defaults so legacy records remain readable.
**Critical hook fix:** `is_barrier_violation()` in `hooks/lib.sh` no longer blocks the orchestrator (empty `agent_type`) from reading `briefs/`, `cleanup/`, and `self-assessment` artifacts — restoring the user-facing brief-relay protocol declared in `commands/rnd-start.md`. Barrier still enforced for `rnd-verifier`, `rnd-proof-gate`, `rnd-polisher`. Bidirectional regression test added.
**Cards:** Four new corpus entries — planner property-shape generation (×2) and verifier counter-example interpretation (×2 for Elixir and TypeScript). Corpus 119 → 123.
**Perf:** `lib/card-retrieve.sh` rewritten from per-card xargs+jq (~290 subprocess forks on the full corpus) to a single-awk-pass — 1.16s → 0.04s on the full builder corpus (~28× speedup).

## 3.25.0 — 2026-05-17

### Python corpus v2: barrier fix, corpus lint, Python coverage, and P-MEASURE-01 canon

**Critical fix:** `/cleanup/` and `/briefs/` barrier paths now require the `.rnd/` artifact-root prefix, so corpus cards under `cards/cleanup/` are no longer blocked during orchestrator card injection.
**Tooling:** New `tests/cards-corpus-lint.test.sh` enforces 6-field frontmatter, sentence-form `scope:`, no Markdown headings in body, and role/lang/id vs directory consistency (strict by default).
**Python coverage:** ~28 new builder cards (FastAPI, Pydantic v2, SQLAlchemy 2, Django ORM, asyncio, httpx, Celery, Flask), 4 verifier cards (pytest/mypy/ruff), 5 reality-auditor cards, 2 cleanup cards, 1 planner card.
**Canon:** New principle `P-MEASURE-01` — gather profiler or benchmark evidence before any performance change.
**Format:** 29 existing cards rewritten to sentence-form `scope:` and stripped of `### Card …` body headings; lint enforces this going forward.

## 3.24.0 — 2026-05-17

### Expand flash-card corpus to v2 with canon principles and language/library tiers

Adds the v2 principle-ladder corpus to plugins/rnd-framework/cards/: four canon principle cards (P-IMPOSSIBLE-01 unrepresentable-states, P-EFFECTS-EDGE-01 functional-core/imperative-shell, P-SMALL-MODULES-01 stable-boundaries, P-PURE-RENDER-01 pure-data-to-UI) anchor a three-tier ladder. Language tier adds 27 cards across Elixir/TypeScript/SQL under builder, reality-auditor, and verifier roles. Library tier adds 43 cards under host-language directories: Elixir-stack Phoenix/Ecto/Bandit/Oban/Sentry-Elixir (cards/<role>/elixir/) and JS/TS-stack Svelte/SvelteKit/Supabase/Sentry-js (cards/<role>/typescript/). All v1 cards retagged with new optional specializes: frontmatter array referencing canon IDs; field is silently ignored by the existing card-retrieve.sh (verified by new tests/card-retrieve-specializes.sh regression test). skills/rnd-cards/SKILL.md documents the field, the ≤40-line soft body budget, the inline-bold label convention, and the canon naming convention P-<TOPIC>-<NN>. Dropped from initial seed scope: Bash and shadcn-svelte. All TS examples use arrow functions and braced if blocks per the project author's JS/TS style preferences. card-retrieve.sh source is byte-identical.

## 3.23.0 — 2026-05-17

### Add flash-card priming system: seed corpus, deterministic retrieval, and orchestrator-level injection at card-receiving spawn points

New plugins/rnd-framework/cards directory ships a 17-card seed library organised by role and language (builder, verifier, cleanup-role, reality-auditor, planner; Python and generic). Each card pairs a good example against a plausibly-worse alternative with a brief rationale — material the model can sample from at generation time. lib/card-retrieve.sh is a deterministic tag-overlap retrieval helper: score = #shared-tags + task-type bonus, sort score DESC then card-id ASC, --max default ${RND_CARDS_MAX_PER_SPAWN:-3}. commands/rnd-start.md, commands/rnd-debug.md, and skills/rnd-multi-judge/SKILL.md gain pre-spawn bash blocks at every card-receiving spawn point (9 total). Cards are concatenated under a Reference examples header and prepended to the agent prompt; when retrieval returns empty the prompt is bytewise identical to today. Per-spawn card_injection audit events go through the existing lib/audit-event.sh. skills/rnd-cards/SKILL.md documents the card authoring format, retrieval contract, and injection convention. rnd-decomposition gains an optional Card tags pre-reg field (role + task_type filtering applies when absent). commands/rnd-cards-propose.md scans calibration.jsonl for recurring FAIL or NEEDS_ITERATION feedback via 4-gram Jaccard clustering and surfaces draft card scaffolds for human review — never auto-inserts. commands/rnd-cards-impact.md measures iterations-to-PASS pre and post a --since rollout date per task_type and emits an improved or no-change or regressed or insufficient-data verdict. None of the five card-receiving agent .md files were modified — injection is orchestrator-level. Five new test suites add roughly 250 assertions. Skill-trim cap for rnd-multi-judge raised from 6750 to 8000 chars to accommodate the legitimate card-injection content.

## 3.22.2 — 2026-05-17

### Lift shared section-parsing helpers to lib.sh; tighten heading-match anchoring across gate hooks

Post-review cleanups for the four cognitive-role gates added in 3.22.1. Two shared helpers — extract_section and is_trivial_section — moved from inline duplication into hooks/lib.sh as a single source of truth; both anomaly-gate.sh and verifier-case-gate.sh now source them, removing ~110 lines of near-duplicate parsing code. extract_section's heading match is anchored to require either end-of-line or a trailing whitespace boundary, so `## Verdict` no longer falsely matches `## Verdicts` — applied across anomaly-gate.sh, verifier-case-gate.sh, and drift-report-gate.sh grep calls. verifier-case-gate.sh further factors its repeated 3-line audit-event emission into a local _emit_event helper. anomaly-gate.sh's trivial-content conditional is inverted to drop a no-op `true` branch. No behavior change — all 108 hook-level tests and the full 18-file suite remain green.

## 3.22.1 — 2026-05-17

### Add four SubagentStop gates, rnd-drift-detector agent, and schema-layer cognitive-style enforcement

Four new SubagentStop gates enforce role-appropriate behaviour at artifact boundaries rather than prompts. anomaly-gate.sh (Reality Auditor) blocks completion when the audit report lacks expected anomaly-detection signals. verifier-case-gate.sh (Verifier) enforces symmetric case sections — every positive test case must be accompanied by a corresponding negative case — preventing coverage asymmetry. cleanup-bloat-gate.sh (Cleanup) is advisory: it fires a gateFired / bloat_aversion_underperform calibration record when the cleanup report shows no net line-count reduction across its changes, surfacing bloat-aversion underperformance without blocking the agent. drift-report-gate.sh (Drift Detector) enforces the drift-report schema — blocks when the report is missing required sections or carries disallowed free-text fields. New rnd-drift-detector agent (sonnet/medium, per-wave) runs between the Builder and Verifier waves and produces $RND_DIR/drift/wave-<N>-drift-report.md, flagging semantic drift between the pre-registration intent and the built implementation before the Verifier evaluates it. Audit observability extended with four new gateFired event names: anomaly_gate, verifier_case_symmetry, bloat_aversion_underperform, drift_detector. Together these changes move cognitive-style enforcement out of prose prompts and into the artifact-gate layer, so deviations are measured rather than just requested.

## 3.22.0 — 2026-05-17

### Add Tier-1 reliability bundle: existence pre-pass, stop conditions, calibration telemetry, Coverage Gaps and Assumptions enforcement

Six new pipeline features. Reality-auditor gains a mechanical existence pre-pass (Step 0) that verifies imports / third-party method calls / RFC + error-code citations / env-var names exist in the form claimed before adversarial experiments; MISSING short-circuits to INVALID_FOUND and emits FALSE_PASS_PROXY on prior PASS. New PreToolUse Write|Edit hook stop-condition-revisions.sh halts on the Nth Write to the same file per task (default 5, RND_STOP_FILE_REVISIONS). New orchestration-level stop conditions: verdict-flip and plan-size halts (RND_STOP_VERDICT_FLIPS, RND_STOP_PLAN_RATIO) using new lib/audit-scan.sh and a required Heuristic ceiling planner meta-field. Pre-registration template now requires an Assumptions / Refuted-by section in both rnd-decomposition and rnd-orchestration skills; Verifier downgrades verdict by one tier when refutation evidence is missing. Calibration schema extended with three optional fields: multiJudge (pre-resolution judge disagreement), task_type (6-value enum with rule-based inference), gateFired (records every new pipeline gate firing). New lib/calibration.sh task_type_window subcommand. New SubagentStop hook coverage-gaps-gate.sh requires a non-trivial Coverage Gaps section in every T<id>-verification.md. Plus: cleanup deletion-ratio one-liner. Every new gate emits gateFired calibration records so false-positive/false-negative rates can be measured post-deployment.

## 3.21.1 — 2026-05-16

### Fix WorktreeCreate hook to echo worktree path to stdout

rnd-framework 3.21.0 added isolation="worktree" to five agent frontmatters but worktree-create.sh only emitted an audit event and exited silently. Claude Code v2.1.83+ requires the WorktreeCreate hook to echo a worktree path on stdout (or return hookSpecificOutput.worktreePath); absence of a path aborts the agent spawn with 'WorktreeCreate hook failed: hook succeeded but returned no worktree path'. This blocked every rnd-builder/rnd-verifier/rnd-cleanup/rnd-polisher/rnd-debugger spawn in 3.21.0. Hook now parses {name, cwd} from the real harness stdin payload (no tool_input.path), resolves the active RND session via active_session_dir(), computes <cwd>/.rnd-worktrees/<rnd-session-id>/<agent-name>, mkdir -p's the parent, emits the audit event, and echoes the path. Test fixture updated to mirror the real stdin contract and lock in the stdout-path assertion.

## 3.21.0 — 2026-05-16

### Add worktree isolation, destructive-git denylist, and closed-loop calibration

## 3.20.7 — 2026-05-12

### Restore pipeline rigor after token-saving regression (effort high on Builder/Arbiter; LOW→sonnet for core roles; full prose verification reports; dismissal-gate Check D for premature DONE)

Four changes that reverse quality regressions introduced by earlier token-savings: (1) rnd-builder and rnd-amendment-arbiter agent effort bumped from `medium` to `high` (the other adaptive core agents — rnd-planner, rnd-verifier, rnd-debugger — were already at `high`); (2) adaptive dispatch policy: LOW criticality now maps to `sonnet` instead of `haiku` for the core roles (Builder, Verifier, Planner, Debugger) — only `rnd-integrator` remains on a lighter model and it is non-adaptive; (3) terse-manifest and lazy-prose pass-receipt paths retired — Builder writes full narrative manifests and Verifier writes a full `T<id>-verification.md` prose report for every verdict including PASS (the `T<id>-pass-receipt.json` artifact is gone); (4) builder-dismissal-gate.sh gains Check D: when a DONE/DONE_WITH_CONCERNS manifest is submitted and the Verifier evidence directory `verifications/T<id>-evidence/` already exists (i.e., a prior verification cycle ran), the gate now requires at least one non-empty `VAL-*.txt` evidence file — blocking premature DONE re-submissions that ignore Verifier feedback. Empty files do not satisfy the gate (a `touch VAL-bypass.txt` would otherwise defeat the check). Also: `tests/agent-effort-frontmatter.test.sh` updated to assert `high` for rnd-builder (was asserting `low` against the prior `medium` baseline — a stale assertion from a previous policy update); `lib/validate-xrefs.sh` PARITY_TABLE no longer requires the retired `pass-receipt.json` term in both verification skill and verifier agent; `CLAUDE.md` Runtime Artifacts section updated to describe verification.md as the only Verifier output.

## 3.20.6 — 2026-05-12

### Broaden builder/cleanup prohibition to cover all pipeline-context leaks (task IDs, planner phase labels, session artifact paths)

## 3.20.5 — 2026-05-12

### Migrate hooks.json to v2.1.139 exec form (args: [])

Every entry in hooks/hooks.json switches from the documented shell-form `"command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/X.sh"` to the v2.1.139 exec-form `"command": "${CLAUDE_PLUGIN_ROOT}/hooks/X.sh", "args": []`. With `args` present, Claude Code spawns the script directly without a shell, so the `${CLAUDE_PLUGIN_ROOT}` placeholder is substituted as a plain string and never needs quoting. Obsoletes the quoting workaround in 3.20.4 and the single-quote-strip fix in 3.20.3, eliminating that class of bug. Raises the minimum Claude Code version dependency to 2.1.139.

## 3.20.4 — 2026-05-12

### Quote CLAUDE_PLUGIN_ROOT in hooks.json to match docs canonical form

Wrap every "${CLAUDE_PLUGIN_ROOT}" path placeholder in hooks/hooks.json with double quotes per the documented shell-form (docs.claude.com/en/docs/claude-code/plugins-reference). Resolves intermittent PreToolUse:Bash hook errors of the form '/bin/sh: ${CLAUDE_PLUGIN_ROOT}/hooks/bash-gate.sh: No such file or directory' observed on Claude Code 2.1.139 when a session is started during cache rotation. Sticks with shell form (not the new v2.1.139 exec form) to preserve compatibility with Claude Code 2.1.117+, the plugin's stated minimum.

## 3.20.3 — 2026-05-12

### Fix hooks.json variable expansion by stripping single quotes around ${CLAUDE_PLUGIN_ROOT}

Removed literal single quotes wrapping ${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh in all 23 hook command entries. /bin/sh treated the single-quoted parameter expression as a literal path component, causing every hook (SessionStart, PreToolUse:Bash, PostToolUse:Bash, UserPromptSubmit, etc.) to fail with 'No such file or directory'. The shell now expands the variable as intended.

## 3.20.2 — 2026-05-11

### Add criticality-driven model dispatch policy

Adaptive per-spawn model override for planner/builder/verifier/debugger keyed on per-task Criticality (LOW=haiku, MEDIUM=sonnet, HIGH=opus); fallback to agent frontmatter when Criticality is absent. Static rebalance: rnd-integrator to haiku, rnd-builder effort to medium. Documented in rnd-orchestration skill and CLAUDE.md.

## 3.20.1 — 2026-05-11

### Add branch-keyed RND artifact partitioning

rnd-dir.sh partitions project-facts.md, roadmap.md, sessions/, .current-session, and .session-git-root under branches/<branch>/ inside the project slug. New --calibration flag returns the un-partitioned calibration.jsonl path. --facts and --roadmap lazily inherit from the default branch on first access. Branch resolved via git symbolic-ref --short HEAD with detached-<sha7> / no-git fallbacks; branch names with .. are rejected.

## 3.20.0 — 2026-05-11

### Add verdict-based escalation gate to multi-judge and trim heavy skill bodies

Multi-judge HIGH-criticality verification now runs a cheap Sonnet/medium first-pass verifier; only FAIL/NEEDS_ITERATION/PASS_QUALITY_NEEDS_ITERATION escalates to full dual-judge with tiebreaker. Set RND_MULTI_JUDGE_ALWAYS=1 to restore pre-gate always-dual-judge behavior. Adds escalationGate object to calibration.jsonl schema (firstPassVerdict, escalated, overturned) so verdict accuracy can be tracked before/after. Trims rnd-multi-judge, code-review, and rnd-doc-polish skill bodies by 20-30% (no rule deletions) to reduce skill-loading overhead in every relevant agent context.

## 3.19.0 — 2026-05-10

### Add Bash output cache + cache-hit advisory to prevent same-command re-runs

PostToolUse Bash now writes stdout (plus stderr if present) to `$session_dir/.bash-cache/<sha>.txt` with a sibling `<sha>.meta.json`, keyed by a 16-char sha-256 of the whitespace-normalized command. PreToolUse Bash detects identical re-runs within `RND_BASH_CACHE_TTL_SECONDS` (default 600s) and emits a non-blocking advisory pointing the agent to the cached file when output is ≥10 lines — addressing the observed "ran `mix test | tail -30`, then re-ran `mix test | grep failure`" pattern. Cache lives inside the session dir (auto-clears each pipeline run; no GC). Hash semantics shared between writer (`post-dispatch.sh`) and advisory (`bash-gate.sh`) via `cmd_hash` in `lib.sh`. New helpers in lib.sh: `_normalize_cmd`, `cmd_hash`, `bash_cache_dir`. Test coverage in `tests/bash-cache.test.sh` (24 assertions: hash stability, writer behavior, hit/miss/stale-TTL/small-output advisory cases, TTL override).

## 3.18.0 — 2026-05-10

### Add opt-in evidence-pack writer and Verifier-side schema gate

Net-new opt-in feature behind RND_EVIDENCE_PACK=1 (Builder) and RND_EVIDENCE_AUDIT=1 (Verifier). New public surfaces: lib/run-tool.sh (pack writer with per-tool relevant_globs input scoping), lib/audit-event.sh (shared {event,task_id,tool,timestamp} emitter), lib/manifest-schema.json (load-bearing — its x-disallowed-fields extension is sourced at runtime), hooks/evidence-pack-gate.sh (PreToolUse Read hook that validates evidence-pack manifests before Verifier reads), lib/tools.json (12-tool registry with structured-output flags + relevant_globs). InformationBarrier.lean extended with evidencePackManifest FileType and verifier-cannot-access-unvalidated-manifest theorem. Builder/Verifier skills documented. Defaults preserved: both flags off.

## 3.17.0 — 2026-05-09

### Add wave-seam polisher agent (Phase 4.5)

Introduces `rnd-polisher` as the 11th specialized agent. It runs at wave-level — one spawn after all per-task cleanup completes — and detects cross-task seam issues: cross-task duplication, naming and API drift across the wave, helpers that should be lifted to shared locations, and structural inconsistencies. Applies mutations in-place and rolls back automatically on any non-PASS re-verification. Output artifact: `$RND_DIR/polish/wave-<N>-polish-report.md`. Barrier extended in `lib.sh` so the polisher is subject to the same information-barrier restrictions as the verifier (cannot read self-assessments, briefs/, or cleanup/). Polish rules added to all 10 kiss-practices language files and to fp-practices/SKILL.md. Phase numbered 4.5, keeping Cleanup at 4 and Integrate at 5 for stability of existing phase references. Lean 4 proof in `InformationBarrier.lean` extended to cover the polisher agent type.

## 3.16.0 — 2026-05-09

### Add mandatory Report Surfacing Protocol to all output styles

All three output styles (scientific, rigorous, pipeline) now carry an identical Report Surfacing Protocol section requiring the orchestrator to print agent/skill report artifacts (plan, design spec, build manifest, verification report, verdict map, reality report, diagnosis, integration report, proof report, amendments, iteration log, audit/review reports, narratives, brainstorm) verbatim before any next-step prompt in the same turn, including autonomous/loop mode. A Forbidden Anti-Patterns subsection lists concrete defects. Pointer reminders added to using-rnd-framework SKILL, README, CLAUDE.md, and the five report-producing commands. Excluded artifacts include builder concern notes, found-issues ledgers, cleanup reports, project facts, calibration jsonl, and audit log.

## 3.15.0 — 2026-05-09

### Add builder-dismissal-gate.sh hook and found-issues.jsonl ledger for structural fix-on-sight enforcement

SubagentStop hook scoped to rnd-builder blocks completion when the build manifest contains dismissal phrases (pre-existing, out of scope, etc.), acknowledges issues without a co-located ledger, or claims success despite test failures. New T<id>-found-issues.jsonl ledger is the only legal escape — entries with decision="escalated" must be acknowledged by the Verifier or the task re-fails. Replaces the failed textual 'never use pre-existing' rules with structural enforcement.

## 3.14.0 — 2026-05-08

### Amendable Pre-Registration (Amendment Flow)

Introduces AMEND_REQUIRED verdict with cited-defect requirement, rnd-amendment-arbiter agent (10th specialized agent), amendment log artifact at briefs/T<id>-amendments.md (barrier-protected), re-prove rule for tasks with Proof: lean, wave-continuation semantics (AMEND_REQUIRED does not block other tasks in wave), and calibration schema extension (amendmentData field).

## 3.13.7 — 2026-05-07

### Cap AskUserQuestion options at 4 across rnd-brainstorm, rnd-debug, rnd-design, rnd-start

Five prompt sites (Phase 3 Explore in rnd-brainstorm, design-approval gate in rnd-start.md:153, design SKILL.md, rnd-debug PASS branch, rnd-start Phase 7) instructed AskUserQuestion calls with 5–7 options, exceeding the tool's hard 4-option cap and causing InputValidationError. Trimmed each to ≤4 (merging near-duplicates or using a two-tier menu) and added a global cap rule plus an explicit per-question option bound to the brainstorm Guidelines and Phase 4.

## 3.13.6 — 2026-05-03

### Fix bash-gate segment dispatch and align is_barrier_violation with Lean proof; add three audit follow-ups

Resolves the two major and three minor findings from /rnd-framework:rnd-audit. (1) bash-gate.sh: moved the git-staging-of-.rnd-paths blocker into check_segment per-segment dispatch (was triggering on any compound command containing both substrings); tightened rnd-dir.sh auto-allow to anchored boundary regex requiring start-of-string or path-slash before the script name; extended push refspec advisory to also catch HEAD:branch form. (2) lib.sh: extended is_barrier_violation to also block agent_type containing 'proof-gate', aligning the runtime with the existing Lean theorem proofGate_cannot_access_self_assessment in proofs/InformationBarrier.lean. (3) validate.sh: added diff -q parity check between the two plugin-dir-base.sh copies. Three new test files cover the changes: bash-gate-git-add-segment.test.sh, lib-is-barrier-violation.test.sh, bash-gate-rnd-dir-boundary.test.sh. All 295 validate checks and full hook test suite pass.

## 3.13.5 — 2026-05-02

### Reconcile skill drift and dedup agent files per audit

Removes ~550 lines of content duplicated between agent files and the skills they preload. Reconciles five skills (rnd-verify, rnd-multi-judge, rnd-orchestration, rnd-iteration, rnd-scaling) so docs match the canonical wave-batched, four-verdict, lazy-prose pipeline. Replaces the cleanup agent's full re-verify spawn with a targeted test-run plus pass-receipt. Adds canonical Decisions Log and User-Facing Briefs sections to rnd-orchestration as the shared home for previously-duplicated agent content.

## 3.13.4 — 2026-04-30

### Audit fixes: dead FP primitives, bash-gate hardening, config drift

Resolves 6 audit findings: removed unused map_lines/filter_lines/reduce_lines from lib.sh; hardened strip_env_prefix against unmatched-quote bypass and refactored bash-gate.sh main to use parse_input; fixed rnd-cleanup.md skills frontmatter format; replaced wc -l with awk in pre-compact.sh; reconciled settings.json with documented defaults (showTurnDuration, allowRead); removed dead validate.ts fallback in setup.sh.

## 3.13.3 — 2026-04-30

### Fix detect_pipeline_phase JSON-only state, cleanup-path barrier consistency, lazy-prose PASS contract drift, and four minor hook and tooling bugs from audit findings

## 3.13.2 — 2026-04-26

### Batch verification per wave with lazy prose on FAIL, decomposition caps, and wave-level iteration

Verifier now spawns once per wave and returns a per-task verdict map at wave-N-verdict-map.json. Happy path writes T<id>-pass-receipt.json instead of full prose; FAIL/NEEDS_ITERATION/PASS_QUALITY_NEEDS_ITERATION auto-materializes the prose report. Planner is capped at max 4 tasks per wave with min 1-hour scope and forced coalescing. Builder/Verifier artifact templates are terse-by-default (structured bullets, no narrative). Phase 5 iteration is wave-level: a single Builder spawn handles all failing tasks in a wave with the full verdict map; budget = highest-criticality task's per-task budget. Information barrier and per-task pre-registration unchanged.

## 3.13.1 — 2026-04-26

### Trim planner maxTurns and verifier overhead to eliminate multi-minute hangs

Drops rnd-planner maxTurns 250 to 100; scopes rnd-experiments mandatory iron law to Correctness criteria only; adds mid-run heartbeat brief triggers to planner (after exploration cache write, after plan.md write) and verifier (after experiments written, after tests run); reconciles all 9 agent assignments in rnd-orchestration from Opus to Sonnet; replaces inline 6-mode failure list in rnd-verifier with forward reference to the 8-mode quick-scan table in rnd-verification skill; deduplicates rnd-verifier.md by 91 body lines (196 to 114) by removing content that already lives in the preloaded rnd-verification skill; adds agent-runtime-budgets.test.sh regression test asserting maxTurns bounds across all 9 agents.

## 3.13.0 — 2026-04-23

### Add per-task cleanup phase and adopt Claude Code v2.1.118 features

Introduce rnd-cleanup agent that sweeps dead code, orphan files, duplicate implementations, and stale comments after each Verifier PASS, applies fixes, and rolls back if cleanup breaks re-verification. Raise minimum recommended Claude Code to v2.1.118 to pick up the agent-type hooks, SendMessage cwd restoration, and prompt-hook re-firing fixes. Ship a curated autoMode.allow extension using the v2.1.118 $defaults keyword and wire 'claude plugin tag' into bump.sh so version bumps emit a validated git tag automatically.

## 3.12.2 — 2026-04-22

### Raise minimum Claude Code version to v2.1.117 and extend info-barrier tests to bfs/ugrep

Primary motivator is the Opus-4.7 1M-context fix in v2.1.117, which restores correct autocompaction behavior for Opus-4.7 pipeline agents. Also added four bfs/ugrep information-barrier test cases in prefer-tools-sh.test.sh to confirm the barrier pattern check catches native-build search tools when used by verifier agents. Corrected stale tool-discipline documentation in CLAUDE.md and skills/committing/SKILL.md that incorrectly claimed cat/grep/find are blocked by bash-gate.sh — they are not; only sed and awk are blocked.

## 3.12.1 — 2026-04-21

### Inject tool-discipline guidance into orchestrator session

Adds a Tool Discipline section to the using-rnd-framework skill, placed before the session-start trim headers so it is injected into the orchestrator context at session start. Covers the four gate-hook rules the model hit most often — temp files ($RND_DIR vs /tmp), file read/write (Read/Write vs cat/echo), search/listing (Grep/Glob vs grep/find/ls), iteration (Grep alternation or parallel Bash calls vs for/while/until loops), and inline interpreter code (project files only vs -c/-e). Each bullet names both the blocked pattern and the allowed alternative so the guidance is proactive, not only reactive via the hook block message. Pipeline subagents already had this guidance in their system prompts; this closes the gap for the main session.

## 3.12.0 — 2026-04-20

### Pipeline tier selection for rnd-start

Adds a Phase 0.1 tier-selection prompt at the top of /rnd-framework:rnd-start. The user picks Prototype, Standard (current default), or High-stakes before discovery begins — via AskUserQuestion or inline --tier=... flag. Prototype tier short-circuits the pipeline: no Planner, Builder, Verifier, or Integrator spawned; orchestrator implements inline and shows the diff. Standard tier is the current full-pipeline behavior. High-stakes tier applies two overrides during execution — Reality Audit runs for every task (not just those declaring External dependencies) and every HIGH-criticality task gets multi-judge consensus automatically. Adds an explicit upgrade path from Prototype to Standard mid-session when the user decides exploration is now worth verifying. Release for real-session testing before hardening.

## 3.11.0 — 2026-04-20

### Add Planner self-review checklist

Planner now runs a fresh-eyes self-review against plan.md before notifying the orchestrator — spec coverage, placeholder scan, VAL traceability, identifier consistency, external-dependency completeness, and Verifier test on each Correctness criterion. Catches plan-level mistakes that would otherwise cascade through Build and Verify.

## 3.10.0 — 2026-04-20

### Collaborative pipeline: anti-popularity brainstorming, cross-phase decisions log, barrier-protected user-facing briefs, artifact trims

Shifts the framework toward iterative collaboration without sacrificing the automation-friendly pipeline.

Key changes:
- /rnd-framework:rnd-brainstorm Phase 3 now requires naming the LLM-default baseline privately, then diverging. At least one direction must be road-less-traveled and at least one must question the problem framing. New 'Diverge before you converge' guideline.
- rnd-design skill softened anti-popularity rules (escape hatch when constraints only admit conventional approaches) plus a Verification Checklist item.
- New $RND_DIR/briefs/decisions.md cross-phase structured judgment log: Planner, Builder, Debugger, and Integrator append entries when rejecting real alternatives. Each entry records options, chosen option, why, and flip condition. Explicit-fork discipline requires narrating the fork in agent output before logging.
- New $RND_DIR/briefs/*-briefs.md user-facing narratives: plan-briefs.md, T<id>-briefs.md, wave-<N>-briefs.md. Agents write them and fire [user-brief] SendMessages; orchestrator relays to user chat. Keeps the developer informed during background agent work.
- Information barrier extended to cover /briefs/ paths: hooks/lib.sh is_barrier_violation now matches both self-assessment and /briefs/ path segments. read-gate.sh, glob-grep-gate.sh, and bash-gate.sh all enforce. Triple protection: orchestrator policy, Verifier startup self-check, and mechanical hook layer.
- rnd-verifier: Information Barrier section, startup self-check, and Rules extended to forbid /briefs/ paths.
- rnd-start: new User-Facing Brief Relay section documenting the orchestrator's relay protocol and the no-leak-to-Verifier constraint.
- Artifact trims to reduce token footprint: evidence files only on FAIL or NEEDS ITERATION verdicts (skip on PASS); self-assessment uses a one-line minimal form for plain DONE status; Builder manifest uses a skinny form for Criticality: LOW tasks.
- 7 new read-gate.test.sh cases for the /briefs/ barrier, including confirmation that the bare word 'brief' in a non-/briefs/ path (e.g. debrief.ts) is not blocked.
- CLAUDE.md updated to document the new artifact layout and the extended information barrier.

All 281 plugin validation checks pass. All hook test suites (read-gate, glob-grep-gate, bash-gate) pass.

## 3.9.0 (2026-04-20)

### Token Optimization & Model Efficiency

**Agent Model Downgrades (Major Cost Reduction)**
- `rnd-planner`: opus/xhigh → sonnet/high
- `rnd-verifier`: opus/xhigh → sonnet/high  
- `rnd-debugger`: opus/xhigh → sonnet/high
- `rnd-data-scientist`: opus/medium → sonnet/medium
- **Impact**: ~75% reduction in token costs for typical pipelines

**Multi-Judge Verification Now Opt-In**
- Changed from default 2-judge + tiebreaker for HIGH tasks to single-judge default
- Multi-judge consensus available via `--multi-judge` flag or `Verification: multi-judge` annotation
- **Impact**: Eliminates 3× token multiplier for high-criticality tasks unless explicitly requested

**Conditional Phase Execution**
- Proof Gate now only runs when task has `Proof: lean` annotation AND Lean is available
- Reality Audit now only runs when task has `External dependencies` declared
- **Impact**: Reduces unnecessary agent spawns for tasks without external deps or formal proof requirements

**Information Barriers Preserved**
- All read-gate.sh protections remain intact
- Verification independence maintained with single-judge default
- Framework quality gates unchanged

## 3.8.0 — 2026-04-18

### Remove read-side tool-discipline gates (cat, head, tail, grep, rg, find)

Drop the `cat`, `head`/`tail` (with file arg), `grep`/`rg` (recursive or with file arg), and `find` blocks from `hooks/bash-gate.sh`. These gates tried to steer Claude toward the Read/Grep/Glob tools but fought training-level habits and triggered excessively on benign one-shot commands, generating noise without preventing anything dangerous. Write-side gates (`sed`/`awk`/`echo>file`/`printf>file`), interpreter blocks (`python -c`/`node -e`/`bun -e`/`perl -e`/`ruby -e`), shell-loop guard, `/tmp` redirect guard, information barrier, DB destructive guards, and git-add-`.rnd/` protection are all unchanged — those have concrete behavioral reasons (hang risk, silent file mutation, context leaks, data loss) rather than stylistic preference. Updates `tests/prefer-tools-sh.test.sh` and `tests/prefer-tools-sh-refactor.test.sh` to match: read-side commands now assert `allowed` / exit 0 instead of `blocked:` / exit 2. Also fixes pre-existing `tests/agent-effort-frontmatter.test.sh` (expected the three Opus agents to use `effort: medium` — v3.7.0 bumped them to `xhigh`; test updated to match the source of truth). Updates tool-discipline wording in `CLAUDE.md`, `README.md`, `skills/prefer-system-tools/SKILL.md`, and `skills/hook-authoring/SKILL.md`.

## 3.7.0 — 2026-04-17

### Adopt v2.1.111-2.1.113 features and trim session bootstrap

Dedupe the 18-line agent table in skills/using-rnd-framework/SKILL.md with a one-paragraph pointer to CLAUDE.md §Execution Model, saving ~125 tokens per SessionStart fire (including every compaction). Raise effort from medium to xhigh (v2.1.111) for the three Opus agents (rnd-planner, rnd-verifier, rnd-debugger) for deeper reasoning on hard tasks. Add sandbox.network.deniedDomains (v2.1.113) with a default denylist (pastebin.com, hastebin.com, 0x0.st, transfer.sh) as defense-in-depth against accidental exfiltration by Builder/Reality-Auditor agents. Drop the now-default showTurnDuration:true from settings.json. Remove the unused defer_json() helper from hooks/lib.sh and its test — it was flagged in CLAUDE.md as 'available infrastructure' but had zero call sites. Document four v2.1.113 features in CLAUDE.md: find -exec/-delete tightening (plugin's blanket find block already covers this), 10-minute subagent stall timeout (does not resolve the rnd-integrator hang on its own), native CLI binary, and sandbox.network.deniedDomains.

## 3.6.0 — 2026-04-17

### Fix builder permission denials + audit cleanup

Replaced mode: "auto" with mode: "acceptEdits" across 13 pipeline-agent spawn sites in 6 files (commands/rnd-start, commands/rnd-debug, skills/rnd-build, skills/rnd-verify, skills/rnd-integrate, skills/rnd-multi-judge) and rewrote the rationale in skills/rnd-orchestration. Empirically, mode: "auto" denied project-file Edit/Write for team-spawned Builders on Claude Code 2.1.112, contradicting the 3.4.1 fix claim. Also addressed six minor issues from codebase audit: dropped stale v2.1.81 parenthetical in session-start.sh; extended is_code_file in lib.sh to recognize .lean/.kk/.ml/.mli; de-namespaced skills field in rnd-proof-gate.md for agent parity; added whole-command-allow clarifying comment in bash-gate.sh; updated CLAUDE.md tool-discipline wording; taught check_echo_redirect to strip 2>&N and 2>/dev/... stderr redirects so "echo foo 2>&1" is allowed while "echo foo > /file" remains blocked; added tests/bash-gate-echo-redirect.test.sh covering the three cases.

## 3.5.1 — 2026-04-17

### Fix format-on-save command injection and deduplicate hook barrier/phase logic

Replace eval with array-split invocation in format-on-save.sh to close a command-injection vector via tool_input.file_path (regression test added). Extract is_barrier_violation and detect_pipeline_phase helpers into hooks/lib.sh, replacing 5 duplicated sites across read-gate.sh, glob-grep-gate.sh, bash-gate.sh, statusline.sh, session-title.sh. Also: add hookEventName:"PermissionDenied" to permission-denied.sh output, switch _ver_gte to explicit IFS='.' read -ra, fix duplicate example in plugin-dir-base.sh doc header (both copies), and rename the untracked agent-effort-frontmatter test into the tests/*.test.sh convention so run-tests.sh picks it up.

## 3.5.0 — 2026-04-17

### Require options after brainstorm

Strengthen rnd-brainstorm Phase 6 to mandate AskUserQuestion for next-step selection; forbid ending the session with a plain-text 'plan saved, run X' message. Updated Guidelines to explicitly call out that pattern as a defect.

## 3.4.2 — 2026-04-16

### Restore Content Parity markers in rnd-build and rnd-verify skills

Add a sentence documenting the Builder's external-dependency verification duty to rnd-build/SKILL.md, and a sentence documenting the Verifier's external-contract-conformance sweep to rnd-verify/SKILL.md. validate.sh now reports 281/281 checks passing (was 279/2).

## 3.4.1 — 2026-04-16

### Fix builder agents blocked on Edit/Write under latest Claude Code

Replace mode: "bypassPermissions" with mode: "auto" in 13 pipeline-agent spawn sites across 7 files. On Claude Code v2.1.112 with Opus 4.7, bypassPermissions is not honored for team-spawned (tmux-backed) subagents, so Edit/Write on project files were denied, blocking every build. auto mode uses the in-context auto-approval classifier which propagates reliably to subagents.

## 3.4.0 — 2026-04-16

### Aggressive token reduction for pipeline agents

- **Effort frontmatter on all 8 agents:** Opus agents set to `medium`, Sonnet agents set to `low`. Counteracts the v2.1.94 default-high change — reduces reasoning tokens ~30-40% per agent turn.
- **Skill preload trimming:** Removed rnd-debugging from builder (-85 lines), rnd-orchestration from integrator (-181 lines), rnd-debugging from data-scientist (-85 lines), kiss-practices + fp-practices from debugger. Total: ~430 lines of auto-injected content eliminated per pipeline run.
- **Fixed stale "Required Skills" body text** in 7 of 8 agents to match actual frontmatter.
- **Model/effort routing matrix** added to rnd-scaling skill: maps criticality tiers (LOW/NORMAL/HIGH) to model + effort per agent type, with Agent tool `model` parameter documentation for orchestrator overrides.
- **Criticality-based verifier routing** in /rnd-start Phase 3: LOW/NORMAL → single verifier, HIGH → multi-judge protocol via rnd-multi-judge.
- **Skill prose condensing:** rnd-verification 265→180 lines (-32%), rnd-building 223→180 (-19%), rnd-decomposition 283→160 (-43%). Multi-judge section replaced with pointer, failure modes converted to compact table.

## 3.3.2 — 2026-04-12

### Fix blocked-by ID mismatch in task display

Pipeline tasks displayed Claude Code internal IDs (`#21`) instead of pipeline IDs (`T5`) in blocked-by references. Added `metadata.pipelineId` to TaskCreate calls and rendering instructions to resolve internal IDs to pipeline IDs across rnd-plan, rnd-status, rnd-orchestration, and rnd-build.

## 3.3.1 — 2026-04-12

### Enforce information barrier across Grep, Glob, and Bash tools

Closes the Grep/Glob and Bash bypass vectors found in audit. glob-grep-gate.sh now blocks self-assessment access for Verifier agents (path and pattern check). bash-gate.sh now blocks any command referencing self-assessment files (Section 0, before tool discipline). 28 new barrier test assertions.

## 3.3.0 — 2026-04-11

### Make Reality Audit mandatory per-task with Builder self-declaration and diff-based discovery

Builder manifest now requires External References section with provenance tagging. Reality Auditor runs on every task, reads manifest cross-check, and diff-scans all changed files. Gate 2.5 added — INVALID verdicts are hard gates.

## 3.2.1 — 2026-04-10

### Add missing description parameter to all Agent spawn templates

## 3.2.0 — 2026-04-10

### Enforce multi-agent execution, remove pipeline-state.json

- **Multi-agent enforcement:** Replaced inline build/verify/integrate instructions in rnd-start.md with explicit `Agent()` spawn blocks using `subagent_type`. Each phase now has a concrete code example and a "Do NOT [build/verify/integrate] yourself" prohibition. The orchestrator dispatches to agents — it no longer contains implementation steps. Same pattern applied to rnd-build, rnd-verify, and rnd-integrate skills.
- **Remove pipeline-state.json:** Task status derived from artifact files (`builds/`, `verifications/`, `integration/`). Eliminates 8 orchestrator read/write points and dual-state synchronization risk.

## 3.1.0 — 2026-04-10

### Migrate 9 commands to skills, fix UserPromptSubmit hook schema

- **Commands → skills migration:** rnd-build, rnd-bump, rnd-calibrate, rnd-doctor, rnd-integrate, rnd-narrative, rnd-plan, rnd-validate, rnd-verify moved from `commands/` to `skills/` directories. Cross-reference validation and tests updated for new paths.
- **session-title.sh fix:** Claude Code v2.1.100 requires `hookEventName` and `additionalContext` in UserPromptSubmit hook output. The hook was only emitting `sessionTitle`, causing "Hook JSON output validation failed" on every prompt. Added required fields; `sessionTitle` is now accepted alongside them.
- **bump.sh:** Support `--patch`, `--minor`, `--major` flags (default: `--patch`). The rnd-bump skill now asks the user which version type to bump with a `(Recommended)` suggestion based on change analysis.
- **Lean 4 proofs:** Added lake-manifest.json for proof gate dependencies.

## 3.0.18 — 2026-04-09

### Remove single-flow mode — multi-agent only

Single-flow mode ran build and verification in the same context window, making the information barrier behavioral (prompting) rather than structural (separate contexts). Behavioral barriers fail. Multi-agent is now the only execution mode. Commands (rnd-start, rnd-debug), skills (rnd-orchestration, using-rnd-framework, rnd-scaling, rnd-iteration), agents (rnd-planner), and documentation (CLAUDE.md, README) all updated. rnd-debug now spawns builder + verifier agents instead of running inline.

## 3.0.17 — 2026-04-09

### Fix intermittent UserPromptSubmit hook error

session-title.sh inherited `set -euo pipefail` from lib.sh, causing transient failures (file I/O races, git lock contention) to exit non-zero and display "UserPromptSubmit hook error". Added `set +e` after sourcing lib.sh — advisory hooks must never block prompt submission. Added session-title.test.sh (10 assertions).

## 3.0.16 — 2026-04-09

### Re-introduce write-gate.sh hook for Write/Edit auto-allow on .rnd/ paths

The allowWrite sandbox rule in settings.json does not reliably match in all contexts (particularly subagents). Re-introduce a PreToolUse hook for Write and Edit that auto-allows .rnd/ artifact paths via is_plugin_artifact_path(), mirroring the existing glob-grep-gate.sh pattern. The allowWrite rule is retained as belt-and-suspenders.

## 3.0.15 — 2026-04-09

### Add v2.1.97 upstream support

Statusline refreshInterval + git_worktree display, UserPromptSubmit session title hook, MIN_CLAUDE_VERSION bump to 2.1.97, bash-gate Accept Edits clarification, CLAUDE.md v2.1.94-v2.1.97 documentation

## 3.0.14 — 2026-04-04

### Block shell loops, allow grep pipe filters, fix stale docs

- **Shell loop guard:** bash-gate.sh now blocks `for`/`while`/`until` loops (exit 2) — they hang in the Bash tool. Suggests Glob/Grep alternatives.
- **Grep pipe filter:** `grep`/`rg` without file arguments (stdin filters like `git diff | grep pattern`) are now allowed. Only file-targeting grep (`grep pattern file`, `grep -r`) is blocked.
- **Agent instructions:** All 8 agents now have shell loop avoidance in Tool Discipline.
- **Documentation:** Fix stale references in CLAUDE.md and plugin README (missing hooks, skills, commands). Expand root README with features, commands, architecture. Replace SSH URLs with HTTPS. Delete legacy `.factory/` scaffolding.
- **Test fix:** prefer-tools-sh-refactor.test.sh header-skip uses dynamic `source` line detection instead of hardcoded line count.

## 3.0.13 — 2026-04-04

### Fix bash 3.2 compatibility for macOS stock bash

Replace bash 4.0+ features with POSIX-compatible alternatives. Adds _lower() helper using tr. Fixes all hooks failing on macOS systems without Homebrew bash.

## 3.0.12 — 2026-04-04

### Add per-assertion evidence files to verification pipeline

## 3.0.11 — 2026-04-04

### Add structured preconditions to pre-registration and build verification

## 3.0.10 — 2026-04-04

### Add project facts layer with /rnd-scan and Phase 0 staleness detection

## 3.0.9 — 2026-04-04

### Add pipeline-state.json and align with v2.1.92

## 3.0.8 — 2026-04-02

### Add format-on-save hook, align with Claude Code v2.1.90

## 3.0.6 — 2026-04-01

### Add commit workflow to committing skill

Explicit tool discipline for commit preparation: use Read/Grep tools, never cat/grep; never chain commands with &&.

## 3.0.5 — 2026-04-01

### Add PR creation safety rules to rnd-completion

Never chain git/gh commands when creating PRs. Each command must be a separate Bash call. Use --body-file for long PR bodies.

## 3.0.4 — 2026-04-01

### Add uv and ruff as preferred Python tools

Add Python package management (uv over pip/pip3/pipx) and linting/formatting (ruff) to prefer-system-tools skill, builder agent tool discipline, KISS practices, bun-scripting fallback, and rnd-formatting detection.

## 3.0.3 — 2026-04-01

### Align with Claude Code v2.1.89: PermissionDenied hook, defer helper, version check, env-prefix fix

## 3.0.2 — 2026-03-31

### Remove invalid PermissionDenied hook entry from hooks.json

PermissionDenied is not in Claude Code's Zod schema for hook events despite being listed as a HOOK_EVENT constant in the source. Removing the entry fixes plugin load failure.

## 3.0.1 — 2026-03-31

### Remove write-gate.sh, add path guards and systemMessage output

Remove redundant write-gate.sh hook (sandbox handles /tmp blocking, settings.json allowWrite handles .rnd/ auto-allow). Add absolute-path guards to lib.sh path matchers. Upgrade post-compact.sh from advisory_json to system_message_json for higher-visibility state restoration. Add SubagentStart/SubagentStop lifecycle hooks for pipeline audit logging.

## 3.0.0 — 2026-03-31

### BREAKING: Drop Factory Droid, OpenCode, and quick mode

Focus exclusively on Claude Code. Remove all multi-platform infrastructure.

- **Drop Factory Droid:** Remove `.factory-plugin/` manifests, `DROID_*` env var detection, `.factory` path matching, Factory Droid tool name variants (`Execute`, `Create`)
- **Drop OpenCode:** Remove `.opencode-plugin/` manifests, `opencode-bridge.ts`, `OPENCODE_*` env var detection, `.config/opencode` path matching, lowercase tool name variants
- **Drop quick mode:** Remove `/rnd-framework:rnd-quick` command and all references. Use `/rnd-framework:rnd-start` with single-flow mode for all task sizes
- **Simplify hooks.json matchers:** `Bash|Execute|bash` → `Bash`, `Write|Create|write` → `Write`, etc.
- **Simplify lib.sh regexes:** `(\.(claude[^/]*|factory)|\.config/opencode)/` → `\.claude[^/]*/`
- **Simplify plugin-dir-base.sh:** 7-branch config detection → 3-branch (CLAUDE_PLUGIN_ROOT, CLAUDE_CONFIG_DIR, default)
- **Clean AskUser dual naming:** Replace `AskUserQuestion`/`AskUser` with `AskUserQuestion` everywhere
- **Add PermissionDenied hook:** Advisory-only hook for auto mode denials (v2.1.88+)
- **Add pipeline settings defaults:** `showThinkingSummaries: true`, `showTurnDuration: true`, `spinnerTipsEnabled: false`
- **Refactor bash-gate.sh:** Extract `_args_after_cmd` and `_check_interpreter` helpers, unify interpreter detection
- **Audit fixes:** Remove 25 tracked `.factory/` files, fix validate.sh VALID_TOOLS, tighten manifest regex, document race conditions

## 2.1.0 — 2026-03-30

### Missions-grade planning: enriched plan.md with environment discovery, validation contract, and worker guidelines

Upgrade the planning phase to produce richer, more intelligent plans inspired by Factory Droid's Missions mode. The plan.md format gains 6 new sections while preserving all existing structure.

- **Environment Discovery:** New structured checklist scan in Phase 0 — detects package manager, test framework, CI config, external services, env vars, secrets. Findings presented to user for confirmation.
- **Validation Contract:** Numbered VAL-AREA-NNN assertions with exact Tool + Evidence commands for every Correctness criterion. Verifiers run these commands directly.
- **Testing Strategy:** First-class section documenting test framework, baseline count, exact run commands for unit/integration/live tests, and user testing approach.
- **Worker Guidelines:** Project-specific boundaries (USE/OFF-LIMITS), coding conventions, architecture notes, and design decisions extracted from CLAUDE.md and linter configs.
- **fulfills traceability:** Each task's pre-registration links to specific VAL assertions via a `fulfills` field, creating bidirectional task↔assertion traceability.
- **Infrastructure section:** External services with URLs and auth requirements, off-limits items.

Updated files: rnd-decomposition skill, rnd-planner agent, rnd-start command, rnd-plan command, rnd-verification skill, rnd-building skill, rnd-orchestration skill.

## 2.0.1 — 2026-03-30

### Fix rnd-quick API rate limit by removing model override and condensing command

Removed model: sonnet from rnd-quick frontmatter (only command forcing a model switch) and condensed from 111 lines / 7,630 bytes to 58 lines / 2,750 bytes. All ceremony preserved.

## 2.0.0 — 2026-03-29

### Restore multi-agent architecture, Lean 4 proofs, and dual-mode orchestration

Major release restoring the rigorous multi-agent architecture from v0.13.8 while preserving all post-1.0.0 improvements (cross-platform support, hook consolidation, codebase-dedicated skills, token reductions).

**Agent Restoration:**
- Restore all 8 specialized agents in `agents/` directory: rnd-planner (opus), rnd-builder (sonnet), rnd-verifier (opus), rnd-integrator (sonnet), rnd-debugger (opus), rnd-proof-gate (sonnet), rnd-reality-auditor (sonnet), rnd-data-scientist (opus)
- Remove `permissionMode` from all agents (not supported for plugin agents)
- Update command references to rnd-prefixed format, add AskUser/AskUserQuestion dual naming
- All agents retain v0.13.8 features: model selection, skills preloading, persistent memory, maxTurns, disallowedTools, SendMessage communication, tool discipline, convergent iteration

**Skill Rigor Restoration:**
- `rnd-orchestration`: Dual-mode support (single-flow + multi-agent), Agent Roles section listing all 8 agents, Subagent Coordination, Proof Gate phase documentation, Mission Mode section for Factory Droid Missions integration
- `rnd-verification`: Exhaustive Reporting Discipline, 6 Known Failure Modes, Epistemic Posture, Multi-Judge Mode with agent-spawning protocol, Evidence Standards, Common Rationalizations table
- `rnd-building`: Convergent Iteration, Status Codes table (DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED), exploration cache reading, external dependency verification
- `rnd-multi-judge`: Agent-spawning language restored (spawn 2 independent verifier agents)
- `rnd-scaling`: Proof Gate column in criticality table, dual verification and agent spawning references
- `rnd-decomposition`: Exploration cache writing section, External Dependencies field in pre-registration format
- `rnd-data-science`: Phase 0 Lean Specifications section restored
- `rnd-completion`: Agent cleanup references
- `using-rnd-framework`: Documents both single-flow and multi-agent execution modes

**Lean 4 Formal Proofs:**
- Restore `proofs/InformationBarrier.lean` (3 theorems using native_decide)
- Restore `proofs/ArtifactFlow.lean` (2 theorems using native_decide)
- Restore `proofs/lakefile.lean`, `lean-toolchain` (v4.28.0), `.gitignore`
- Restore `lean-proving` skill and `kiss-practices/lean.md`

**Dual-Mode Execution:**
- `/rnd-framework:rnd-start` supports mode selection between single-flow and multi-agent
- `/rnd-framework:rnd-quick` explicitly scoped as single-flow only with escalation to rnd-start
- `/rnd-framework:rnd-doctor` includes agent health check section

**Cross-Platform Compatibility:**
- Agent tool lists use PascalCase names (Read, Write, Edit, Bash, Glob, Grep, WebFetch)
- Agent skills use `rnd-framework:` prefix to avoid personal skill shadowing
- All 3 plugin manifests preserved (.claude-plugin, .factory-plugin, .opencode-plugin)
- OpenCode bridge preserved unchanged

**Documentation:**
- README.md updated with dual-mode execution docs, 8-agent architecture, updated plugin structure
- CHANGELOG.md 2.0.0 entry
- Root CLAUDE.md updated with agent architecture references

## 1.0.5 — 2026-03-28

### Remove Lean 4 formal verification

Remove proofs/ directory (InformationBarrier.lean, ArtifactFlow.lean, lakefile.lean, lean-toolchain, lake-manifest.json). Remove lean-proving skill and lean.md KISS practices. Remove Proof Gate phase from rnd-start pipeline, rnd-orchestration execution phases, rnd-scaling criticality table, rnd-data-science Phase 0, rnd-doctor Lean toolchain check, and README skill/agent/artifact listings. Remove proof-gate keyword from read-gate.sh information barrier and corresponding test cases. Remove validate_proofs from validate.sh. All 222 validation checks pass.

## 1.0.4 — 2026-03-28

### Audit fixes: deduplicate config-dir resolution, extract validate.sh cross-refs

Extract `_resolve_config_dir()` in hooks/lib.sh to eliminate duplicated config-dir resolution logic between `active_session_dir()` and plugin-dir-base.sh. Extract ~200 lines of cross-reference and content parity validation from lib/validate.sh into lib/validate-xrefs.sh, keeping both files under 250 lines. All 225 validation checks pass.

## 1.0.3 — 2026-03-28

### Purge stale multi-agent references from docs, commands, and skills

After the v1.0.0 single-flow migration, CLAUDE.md, README.md, rnd-resume, rnd-brainstorm, rnd-narrative commands, and rnd-calibration, rnd-orchestration, code-review, rnd-roadmapping, using-rnd-framework skills still referenced the removed multi-agent architecture (8 named agents, agent spawning, worktree isolation). Replaced with single-flow terminology. Updated hook filenames: prefer-tools.sh → bash-gate.sh, post-tool-use.sh + observation-mask.sh → post-dispatch.sh. Also updated opencode-bridge.ts comments.

## 1.0.2 — 2026-03-28

### Add 5 codebase-dedicated skills

New skills: hook-authoring, plugin-architecture, bash-hook-testing, plugin-versioning, lib-sh-patterns — covering hook conventions, multi-platform plugin structure, test framework patterns, release workflow, and lib.sh shared utilities.

## 1.0.1 — 2026-03-28

### Fix post-1.0.0 breakage: stale agent references, AskUser cross-platform parity

Fix 28 content parity validation failures caused by the 1.0.0 agent removal. Redirect PARITY_TABLE entries in `lib/validate.sh` from deleted agent files to their new locations in commands and skills. Remove entries that were self-contained within a single artifact (data-science skill, multi-judge file naming).

Fix `rnd-brainstorm` and all other conversation-driven commands hanging in Factory Droid. The commands referenced `AskUserQuestion` (Claude Code tool name) but Factory Droid only has `AskUser`. Update all 18 commands and 4 skills to use dual naming (`AskUserQuestion`/`AskUser`). Add `AskUser` to VALID_TOOLS in validate.sh.

Clean up stale agent terminology across 7 skills: replace "spawn agent", "Builder agents", "Verifiers", "dispatch one agent per task" with phase-based language matching the single-flow architecture.

## 1.0.0 — 2026-03-28

### BREAKING: Single-flow execution, remove all agents, merge hooks

Remove all 8 agents (rnd-planner, rnd-builder, rnd-verifier, rnd-integrator, rnd-debugger, rnd-data-scientist, rnd-proof-gate, rnd-reality-auditor). All pipeline phases now run sequentially in one session — no agent spawning, no worktree isolation, no per-agent context overhead. Phase-specific instructions were already covered by corresponding skills (rnd-decomposition, rnd-building, rnd-verification, rnd-integration, etc.); commands now invoke skills directly instead of spawning agents.

Refactor all 10 orchestration commands (rnd-start, rnd-plan, rnd-build, rnd-verify, rnd-integrate, rnd-debug, rnd-review, rnd-audit, rnd-roadmap, rnd-quick) to replace "Spawn agent with subagent_type" instructions with "Invoke skill" + inline execution.

Merge PreToolUse hooks: db-guard.sh + prefer-tools.sh → bash-gate.sh (1 process spawn instead of 2 for every Bash tool call). Merge PostToolUse hooks: post-tool-use.sh + observation-mask.sh → post-dispatch.sh with tool_name-based routing. Add session-based early exit to post-dispatch.sh (skip all work when no active pipeline session).

Update hooks.json: PreToolUse Bash entries reduced from 2 to 1; PostToolUse entries reduced from 3 to 1 (single matcher covers Write|Create|write|Edit|edit|Bash|Execute|bash). Update OpenCode bridge routing tables to use new script names.

Update skills: rnd-orchestration, rnd-scheduling, rnd-multi-judge, rnd-scaling, rnd-local-experts — remove agent-spawning language, replace with skill invocation and sequential execution references.

Information barrier preserved: read-gate.sh still blocks self-assessment reads mechanically. The model writes the self-assessment during build but cannot re-read it during verification.

## 0.14.14 — 2026-03-28

### Add database guard hook, OpenCode platform support

Add `db-guard.sh` PreToolUse hook that blocks destructive database operations across all platforms. Blocks `mix ecto.reset`/`ecto.drop` without `MIX_ENV=test`, direct deletion of `.db`/`.sqlite`/`.sqlite3` files, PostgreSQL destructive commands (`dropdb`, `DROP DATABASE`, `pg_restore --clean`), MySQL destructive commands (`mysqladmin drop`, `DROP DATABASE`), and SQLite destructive SQL (`DELETE FROM`, `DROP TABLE`). Issues advisory warnings for `MIX_ENV=dev ecto.create`/`ecto.migrate`. Registered before `prefer-tools.sh` in hooks.json so database guards run first.

Add OpenCode as third supported platform alongside Claude Code and Factory Droid. Add `opencode-bridge.ts` that translates OpenCode JS hook events to shell script calls via `Bun.spawn`. Widen path regexes in `lib.sh`, `prefer-tools.sh`, `plugin-dir-base.sh` to match `~/.config/opencode/` paths. Add `OPENCODE_CONFIG_DIR`/`OPENCODE_CONFIG` detection to config directory resolution. Widen hook matchers to include lowercase tool names (`bash`, `read`, `write`, `edit`, `glob`, `grep`). Update CLAUDE.md documentation for tri-platform support.

## 0.14.13 — 2026-03-27

### Fix all audit findings: entropy, stdin parsing, unused code, style consistency

Increase session ID entropy from 2 to 4 bytes in all 3 plugin-dir-base.sh copies; widen SESSION_ID_REGEX and SESSION_ID_RE to accept 4-8 hex chars for backward compatibility. Standardize stdin parsing in write-gate.sh and glob-grep-gate.sh to use parse_input from lib.sh. Remove unused parse_input_stdout function from lib.sh. Remove redundant set -euo pipefail from setup.sh and instructions-loaded.sh (lib.sh provides it). Update tests for new regex and removed function.

## 0.14.12 — 2026-03-27

### Fix audit findings: verifier rules, session validation, hook consistency

Remove contradictory "proposed fix" mandate from rnd-verifier.md that conflicted with the diagnosis-only rule. Add SESSION_ID_RE validation to active_session_dir fast path in lib.sh for defense-in-depth. Standardize explicit exit 0 after allow_json in write-gate.sh and glob-grep-gate.sh. Extract repeated interpreter-blocked message into readonly constant in prefer-tools.sh.

## 0.14.11 — 2026-03-27

### Add rnd- prefix to all command filenames for Droid namespace disambiguation

Rename all 19 command files from `X.md` to `rnd-X.md` (e.g., `start.md` → `rnd-start.md`). In Factory Droid, which doesn't auto-namespace plugin commands, these now appear as `/rnd-start` instead of `/start`, preventing collisions with other plugins. In Claude Code, they appear as `/rnd-framework:rnd-start`. Updated all cross-references across 29 files (CLAUDE.md, README, 16 commands, 12 skills, 1 agent, validate.sh, tests). Added command-to-command cross-reference validation to validate.sh (325 total checks).

## 0.14.10 — 2026-03-27

### Optimize hook performance: 44% reduction in per-cycle overhead

Cache active session base-dir path in `.active-base-dir` file to avoid re-running `git rev-parse` + `shasum` (~15ms) on every hook invocation. Collapse multiple sequential `jq` subprocess spawns into single calls across 7 hooks (parse_input 3→1, post-tool-use 4→1, write-gate 2→1, glob-grep-gate 2→1, task-created, stop-failure, observation-mask). Short-circuit PostToolUse hooks (post-tool-use, task-created, observation-mask) before reading stdin when no active pipeline session exists. Per-cycle hook overhead drops from 183ms to 102ms. Also fix CLAUDE.md: reality-auditor color red→teal, document marketplace.json asymmetry.

## 0.14.9 — 2026-03-26

### Add Factory Droid platform support

Platform shim: config dir detection (DROID_CONFIG_DIR, DROID_PLUGIN_ROOT), path regex widening for ~/.factory/ paths, hooks.json matcher expansion (Bash|Execute, Write|Create). Also includes audit fixes: validate.md reference, shellcheck directives, credential env var support in start.ts.

## 0.14.8 — 2026-03-26

### Add Glob/Grep PreToolUse hooks, align permission regex with is_plugin_artifact_path

Add glob-grep-gate.sh to auto-allow Glob and Grep operations on .rnd/ artifact paths. Tighten prefer-tools.sh Bash auto-allow and check_echo_redirect regexes to require .claude prefix, consistent with is_plugin_artifact_path. Add 18 tests for the new hook.

## 0.14.7 — 2026-03-26

### Fix audit findings: remove dead code, standardize hooks, increase verifier turn limit

Remove unused `_BUN_SAFE_SUBCOMMANDS` from prefer-tools.sh. Replace `ls | grep` with `compgen -G` in statusline.sh. Remove `main()` wrappers from 4 hooks to match majority top-level pattern. Increase verifier agent maxTurns from 100 to 150 for full codebase audits.

## 0.14.6 — 2026-03-26

### Fix hook auto-allow for plugin artifact paths, MCP schema for object-valued attributes, and remove Team Mode from pipeline

Generalize hook auto-allow for plugin artifact paths. Remove TeamCreate/TeamDelete from pipeline commands.

## 0.14.5 — 2026-03-26

### Fix plugin-dir-base.sh missing from plugin cache by adding local copies

## 0.14.4 — 2026-03-26

### Adopt v2.1.84 platform features: agent effort levels, builder worktree isolation, TaskCreated hook

## 0.14.3 — 2026-03-26

### Auto-allow learnings directory reads in read-gate hook

## 0.14.2 — 2026-03-25

### Fix 6 major audit findings

Fix inert cwd-changed.sh hook, remove nonexistent command reference in instructions-loaded.sh, fix settings.json statusline extension, extract shared plugin-dir-base.sh to eliminate duplication, add proof-gate to read-gate.sh information barrier

## 0.14.1 — 2026-03-25

### Condense command and skill prose for token reduction

Tightened prose in 5 files: start.md (390→223), verify.md (137→130), rnd-verification (311→180), rnd-building (262→180), rnd-decomposition (223→153). Total: 1,323→866 lines (-457, 35% reduction). Replaced duplicated multi-judge protocol summaries with skill references. Compressed templates, converted verbose conditionals to tables, removed redundant explanations. All behavioral semantics preserved.

## 0.14.0 — 2026-03-25

### Add Team Mode for builder agents

start.md Phase 2 and Phase 4 now wrap builder spawning with TeamCreate/TeamDelete for session-scoped team lifecycle. Builder Agent calls include team_name and name parameters for addressability. build.md standalone command follows the same pattern. rnd-builder.md gains a concise team awareness section. Verifier, Proof Gate, and Reality Audit spawning unchanged.

## 0.13.8 — 2026-03-25

### Add criticality-driven verification routing (single-judge default)

Added Criticality: LOW | NORMAL | HIGH field to pre-registration format. Renamed MEDIUM tier to NORMAL in rnd-scaling. Default verification mode is now single-judge (1 verifier) for LOW and NORMAL tasks. Multi-judge consensus (2 verifiers + tiebreaker) is reserved for HIGH criticality tasks (security, auth, data integrity, complex algorithms, data migrations, financial calculations, architectural decisions). Iteration budgets scale with criticality: LOW=2, NORMAL=3, HIGH=5. Updated start.md Phase 3, verify.md, rnd-multi-judge, rnd-verification, rnd-decomposition, and rnd-planner.

## 0.13.7 — 2026-03-25

### Trim agent skill preloads and fold failure modes into verification

Trimmed using-rnd-framework from 167 to 53 lines by removing reference tables. Folded 6 critical failure modes and 14 red flag phrases into rnd-verification as a compact appendix. Removed rarely-used skill preloads from 5 agents: rnd-debugging/rnd-experiments/rnd-failure-modes from verifier, fp-practices from builder, lean-proving from data-scientist, kiss-practices from proof-gate and reality-auditor. Updated validate.sh parity checks. All 293 validation checks pass.

## 0.13.6 — 2026-03-25

### Refactor hooks with FP toolkit and expand clean-code skills

## 0.13.5 — 2026-03-25

### Adopt v2.1.83 features: CwdChanged/FileChanged hooks, fix SessionStart JSON format

Add CwdChanged hook (warns on cross-repo directory change during active session) and FileChanged hook (advises on external .rnd/ artifact edits). Remove additional_context top-level key from SessionStart JSON output — emit only hookSpecificOutput to match Claude Code's expected format.

## 0.13.4 — 2026-03-25

### Remove stale extract-patterns.ts and slop gate references

The slop gate system was removed but references survived in debug.md, quick.md, prefer-tools.sh, and code-review SKILL.md, breaking both debug and quick pipelines at setup.

## 0.13.3 — 2026-03-24

### Allow head/tail as pipe filters in prefer-tools hook

## 0.13.2 — 2026-03-24

### Prevent pipeline task ID leakage into project code

## 0.13.1 — 2026-03-24

### Block inline interpreter execution and /tmp writes

Add interpreter inline ban to prefer-tools.sh: blocks python/python3/node/bun/perl/ruby
with -c/-e flags or as bare pipe targets, while allowing file execution (bun test,
python -m pytest, node script.js). Add /tmp redirect detection for Bash tool and /tmp
write block for Write/Edit tools in write-gate.sh. Add ## Tool Discipline section to
all 8 agent markdown files. 183 prefer-tools + 21 write-gate test assertions (304 total).

## 0.13.0 — 2026-03-23

### Migrate all hooks from TypeScript to plain bash, remove regex verification systems

## 0.12.6 — 2026-03-23

### Add Reality Auditor agent for external service verification

## 0.12.5 — 2026-03-23

### Add 17 management tools for full framer-api coverage

Collection ordering, code file management, style removal, locale management, redirect management, plugin data persistence, and code validation tools. Achieves complete coverage of all request-response-compatible framer-api operations.

## 0.12.4 — 2026-03-23

### Add asset, page, and component variable tools

New tools: add_image, add_svg, add_text, clone_web_page, clone_design_page, get_breakpoint_suggestions, add_breakpoint, get_component_variables, add_component_variables, remove_component_variables, set_variable_order.

## 0.12.3 — 2026-03-23

### Add 10 node/canvas/misc tools and upgrade MCP protocol to 2025-11-25

New tools: get_parent, set_parent, get_rect, walk_tree, select_nodes, get_selection, zoom_into_view, get_canvas_root, check_permission, notify. Protocol upgraded to 2025-11-25.

## 0.12.2 — 2026-03-23

### Add component tools, style lookups, and attribute resolution to Framer MCP

New: create_component_node, add_component_instance, add_variant, add_gesture_variant tools. New: getColorStyle and getTextStyle lookups. Enhanced: set_node_attributes resolves cs:Name to ColorStyle, font to Font instance, inlineTextStyle to TextStyle. Enhanced: create/update_text_style support color, tag, alignment, transform.

## 0.12.1 — 2026-03-23

### Rewrite all 11 Framer skills with Academy-sourced methodology

Each skill now includes Methodology (sequencing, decision points, best practices), Patterns (cookbook MCP tool call examples), Anti-Patterns, and Academy References. Total skill content grew from 1,078 to 3,938 lines.

## 0.12.0 — 2026-03-22

### Move to private repo, proprietary license

## 0.11.33 — 2026-03-22

### Fix observation-mask test isolation and injection-scanner stdout fallback

## 0.11.32 — 2026-03-22

### Add formatting and bump options to debug pipeline ship flow

## 0.11.31 — 2026-03-22

### Add SendMessage Communication sections to agent files

## 0.11.30 — 2026-03-22

### Auto-allow plugin lib/ script invocations to stop repetitive permission prompts

## 0.11.29 — 2026-03-22

### Rename marketplace to oleksify-plugins

## 0.11.28 — 2026-03-22

### Fix Lean 4 proof gate activation and detection

## 0.11.27 — 2026-03-22

### Fix prefer-tools hook evasion via compound shell commands

## 0.11.26 — 2026-03-22

### Add push protection and prompt injection scanner

Inspired by dwarvesf/claude-guardrails: (1) prefer-tools.ts now blocks git push to main/master/production branches — deterministic enforcement replacing advisory CLAUDE.md instruction. (2) New injection-scanner.ts PostToolUse hook scans Read, Bash, and MCP tool output for 14 common prompt injection patterns and emits advisory warnings. Registered for PostToolUse/Read and PostToolUse/Bash events. Uses import.meta.main guard for safe test imports.

## 0.11.25 — 2026-03-22

### Fix audit findings

Fix Bun.file().exists() used on directory path in pre-compact.ts extractCurrentTaskId() — always returned null for existing builds directories. Move generateNeedle() from pre-compact.ts to lib.ts to prevent compact-needle tests from silently failing (module-level process.exit killed test runner). Add observation-mask.ts to CLAUDE.md and README.md file trees. Fix README.md command count (18→19).

## 0.11.24 — 2026-03-22

### Migrate hook filesystem I/O to Bun-native APIs

Replace readFileSync/writeFileSync with Bun.file().text(), Bun.file().json(), and Bun.write() across 5 hook files. post-compact.ts is now fully node:fs-free. Remaining node:fs imports (existsSync for directories, appendFileSync, mkdirSync, readdirSync, statSync) have no Bun alternatives.

## 0.11.23 — 2026-03-22

### Add research-backed failure patterns to catalog

Expand rnd-failure-modes from 11 to 18 patterns with 7 new builder/orchestrator drift patterns extracted from 2024-2026 LLM reliability research: Pipeline Ceremony Shortcut, Attention Decay Drift, Resource Hallucination, Mapping Hallucination, Self-Deception Cycle, Observation Flooding, Post-Compaction Amnesia. Each maps to a concrete mitigation already in the framework. Add 4 new red flag phrases.

## 0.11.22 — 2026-03-22

### Fix roadmap mode skipping verification

Roadmap milestones were being completed inline without multi-judge verification. Root cause: recursive /rnd-framework:start invocation when already inside one caused the orchestrator to silently drop pipeline phases. Fix adds anti-recursion guidance to roadmap.md and a Milestone Execution and Verification section to the roadmapping skill that marks inline completion as an anti-pattern.

## 0.11.21 — 2026-03-22

### Research-driven improvements from LLM drift and hallucination literature

Six improvements based on 2024-2026 academic work: (1) Release automation — add "Bump version, tag and push" option to Phase 6 menus in start.md, quick.md, and rnd-completion skill. (2) SCAN re-anchoring — mandatory compliance re-statement before each Red-Green-Refactor criterion in the builder skill, restoring attention weights as context grows. (3) Property-based testing — guidance in builder skill for when to prefer property tests over specific-output tests. (4) Post-compact verification — needle-in-the-haystack challenge after context compaction to detect degraded recall. (5) Observation masking — context management guidance plus PostToolUse/Bash hook that advises when output exceeds 50 lines. (6) Criticality-based verification scaling — LOW/MEDIUM/HIGH tiers in rnd-scaling skill with differentiated judge count and iteration budgets.

## 0.11.20 — 2026-03-22

### Consolidate PostToolUse hooks and add write-gate

Merge audit-log.ts, slop-gate.ts, and evidence-warn.ts into a single post-tool-use.ts handler, eliminating 2 redundant Bun process spawns per Write/Edit operation. Convert slop-gate.ts and evidence-warn.ts to pure library modules. Extract shared helpers (extractWriteEditContent, extractFilePath, activeSessionDir, isoTimestamp) to lib.ts. Clean up lifecycle hooks (stop-failure, pre-compact, post-compact) to use shared helpers. Add write-gate.ts PreToolUse hook for Write/Edit to auto-allow .rnd/ path operations without permission prompts.

## 0.11.19 — 2026-03-20

### Remove chunk-gate hook and 30-line chunking workflow

Delete chunk-gate.ts and its test, remove Write/Edit PreToolUse entries from hooks.json, remove .planning-phase marker from commands, update builder agent to use bypassPermissions, clean all chunk references from skills and docs.

## 0.11.18 — 2026-03-20

### Inline quick mode verification to avoid API rate limits

Quick mode now verifies inline instead of spawning a separate verifier agent. Reduces API calls from 3+ to 1 per pipeline run, preventing 429 rate limit errors.

## 0.11.17 — 2026-03-20

### Add deterministic pattern extraction and multiline slop gate analysis

Fix slop gate not catching project-specific CLAUDE.md rule violations. New lib/extract-patterns.ts runs in all commands for reliable coverage. Multiline pattern support in slop-gate.ts enables cross-line detection.

## 0.11.16 — 2026-03-20

### Add pre-commit code formatting step

New `rnd-formatting` skill that detects the project's code formatter (biome, prettier, mix format, cargo fmt, ruff, gofmt, etc.) from config files and runs it on pipeline-changed files. Runs automatically before doc-polish in both `/start` Phase 6 and `/quick` Step 4. Formatter detection is config-based — never assumes a default. Formatting failures are advisory and do not block the pipeline.

## 0.11.15 — 2026-03-20

### Add pipeline learning extraction

Auto-captures non-obvious gotchas from iteration cycles to the user's Learning Library (`$CLAUDE_CONFIG_DIR/learnings/`). When a build fails verification and the fix reveals something non-obvious, the orchestrator extracts the gotcha and writes it to the appropriate language file. Builder prompts now include "Known gotchas" from matching learnings files, preventing agents from repeating known mistakes across sessions.

## 0.11.14 — 2026-03-20

### Add multi-session roadmapping

New `/rnd-framework:roadmap` command and `rnd-roadmapping` skill for planning work that spans multiple sessions across multiple days. A roadmap decomposes a broad goal into milestones (3-7), each executed as a separate pipeline session via `/start`. The `/start` command now checks for existing roadmaps in Phase 0 and suggests the next milestone. Session completion (`rnd-completion`) automatically updates the roadmap after SHIP verdicts. Added `--roadmap` flag to `rnd-dir.sh` for path resolution and a "Multi-session" tier to `rnd-scaling`.

## 0.11.13 — 2026-03-20

### Adopt Claude Code v2.1.80 features

Added `effort` frontmatter to all 30 skills and 18 commands — low for reference/guidance, medium for procedural workflows, high for orchestration commands. This lets Claude Code adjust reasoning effort per skill/command invocation, saving tokens on simple operations. Added statusline script (`hooks/statusline.ts`) that displays rate limit usage (5h/7d windows) and current pipeline phase in the Claude Code status bar. Documented `source: 'settings'` inline plugin declaration in README as an alternative to marketplace installation.

## 0.11.11 — 2026-03-19

### Adopt Claude Code v2.1.79 features

Added `SessionEnd` hook (`hooks/session-end.ts`) that auto-clears the active RND session when a Claude Code session closes or switches via `/resume`. Previously, stale `.current-session` markers could persist because SessionEnd hooks didn't fire on `/resume` — fixed upstream in v2.1.79. Also documented `CLAUDE_CODE_PLUGIN_SEED_DIR` multi-directory support in README for org-wide plugin distribution. Upstream improvements to non-streaming API fallback (2-minute timeout) and enterprise 429 retry passively improve pipeline agent reliability.

## 0.11.10 — 2026-03-18

### Adopt Claude Code v2.1.78 features

## 0.11.9 — 2026-03-18

### Fix Lean detection in Proof Gate for subagent PATH

## 0.11.8 — 2026-03-18

### Fix hook security and reduce startup overhead

## 0.11.7 — 2026-03-18

### Add Koka KISS practices and expand Lean 4 with Mathlib style

## 0.11.6 — 2026-03-18

### Update Svelte KISS practices to Svelte 5 runes API

## 0.11.5 — 2026-03-18

### Remove non-functional wellbeing-check hook

## 0.11.4 — 2026-03-18

### Add lib/ to tsconfig, standardize hook error wrapping, simplify readStdin

## 0.11.3 — 2026-03-18

### Tighten .rnd/ auto-allow and fix chunk-gate line count

## 0.11.2 — 2026-03-17

### Fix slop gate to surface findings as advisory context

## 0.11.1 — 2026-03-17

### Audit and harden hooks, rewrite validate.sh as TypeScript

## 0.11.0 — 2026-03-17

### Add Lean 4 formal verification integration

## 0.10.10 — 2026-03-17

### Auto-allow plugin cache reads and update v2.1.77 compatibility

## 0.10.9 — 2026-03-16

### Add experiment-based verification and calibration

## 0.10.8 — 2026-03-16

### Fix bump.sh failing when invoked from plugin cache path

## 0.10.7 — 2026-03-16

### Port all hooks to TypeScript

Replaced all 11 bash hooks and 2 JS hooks with TypeScript equivalents sharing a typed lib.ts utility library. Merged auto-allow-rnd logic into chunk-gate.ts (Write/Edit) and read-gate.ts (Read), eliminating the standalone hook. Deleted lib.sh. Renamed 7 t-prefixed test files to descriptive names, centralized duplicated helpers (computeSlug, createTestEnv, input builders) into helpers.ts, standardized all tests on test() instead of it(). Updated CLAUDE.md and README.md hooks directory trees. 505 tests pass, net -262 lines.

## 0.10.6 — 2026-03-16

### Fix 4 non-functional features

Remove bypassPermissions from builder to restore chunk-gate enforcement. Add anti-deflection rules to prevent dismissing findings as pre-existing. Replace broken cron-based wellbeing with PostToolUse timer hook. Add MANDATORY enforcement language for doc-polish invocation.

## 0.10.5 — 2026-03-15

### Add evidence-based decision grounding

Require Builders to cite file:line evidence for external contracts before coding (Step 2.75). Verifiers now check manifest Evidence Gathered section against code. New evidence-warn PostToolUse hook detects SQL/API patterns and reminds Builders to read schemas.

## 0.10.4 — 2026-03-15

### Fix minor audit cosmetic findings

Fix slop-gate cumulative score double-counting on same-file rewrites, prefer-tools cd-stripping regex precision, standardize resilient hook comments, and replace grep -iq with bash nocasematch in read-gate

## 0.10.3 — 2026-03-15

### Adopt Claude Code latest features

Add PreCompact, PostCompact, InstructionsLoaded, and Setup hooks. Enhance read-gate with agent_type awareness. Add wellbeing cron via SessionStart. Add permissionMode to all agents. Add user-invocable, context:fork, allowed-tools, CLAUDE_SKILL_DIR, and CLAUDE_SESSION_ID to skills. Ship settings.json with spinnerVerbs. Add model to quick and verify commands.

## 0.10.2 — 2026-03-15

### Fix minor audit findings

Compute HOOK_PATH from import.meta.dir in audit-log and slop-gate tests, align generateSessionId() to lowercase hex, consolidate validate.sh frontmatter_val sed pipes

## 0.10.1 — 2026-03-15

### Fix hooks blocking Builder self-assessment writes to .rnd/ paths

## 0.10.0 — 2026-03-15

### Add explained incremental building with chunk-gate enforcement

New chunk-gate PreToolUse hook blocks Write/Edit calls exceeding 30 lines to project files, forcing agents to produce small, reviewable chunks. Builder agent now uses AskUserQuestion after each chunk to present reasoning (WHY + CONNECTS TO) for human approval before proceeding. Planner writes exploration cache to $RND_DIR/exploration/ so downstream agents avoid redundant codebase reads. Builder agents no longer use bypassPermissions to ensure AskUserQuestion pass-through works.

## 0.9.28 — 2026-03-14

### Add developer wellbeing and explained coding

New rnd-wellbeing skill with break suggestions at 90min/2hr/3hr thresholds using cognitive science reasoning, and explained incremental coding principles. Iron Law 7 requires builders to explain before writing and work in logical increments. Break checkpoints wired into start.md between waves and Phase 6. Builder agent preloads the wellbeing skill.

## 0.9.27 — 2026-03-14

### Add standalone narrative command for past sessions

New /rnd-framework:narrative command generates a prose development narrative from any pipeline session's artifacts. Reads plan, build manifests, verification reports, iteration logs, and integration reports. Works with active sessions, most recent session, or specific session IDs. Complements the 'Show development narrative' option in the Phase 6 menu.

## 0.9.26 — 2026-03-14

### Add anti-deflection rule for error handling

Iron Law 6 in builder skill: agents must investigate and fix errors/warnings instead of deflecting with 'pre-existing' as a reason to skip. Context about whether an issue is new or old is allowed, but the response must always be solution-oriented.

## 0.9.25 — 2026-03-14

### Add development narrative option to pipeline completion

New 'Show development narrative' option in Phase 6 (start.md) and Step 4 (quick.md) completion menus. Generates a prose narrative of the pipeline run covering what was built, key decisions and trade-offs, obstacles and iterations, insights gained, and what's left. Generated by the orchestrator from conversation context with RND_DIR artifact fallback for long runs.

## 0.9.24 — 2026-03-14

### Add brainstorming pipeline for idea exploration

New /rnd-framework:brainstorm command — a conversational pipeline that funnels vague ideas into focused, implementable plans through 6 phases: Seed, Expand, Explore, Narrow, Focus, Output. No agents spawned — purely AskUserQuestion driven. Output can be saved or handed to /rnd-framework:start for implementation.

## 0.9.23 — 2026-03-14

### Add functional programming practices skill

New fp-practices skill with five concrete FP principles: pure functions, data transformations over mutation, composition over inheritance, command-query separation, and immutability by default. Each principle includes do/don't rules with code-level examples and a 'when to break' section. Preloaded in the builder agent and loaded during Phase 0 alongside KISS practices.

## 0.9.22 — 2026-03-14

### Fix README kiss-practices language list

README skill table description for kiss-practices now includes Bash and Markdown alongside the existing six languages.

## 0.9.21 — 2026-03-14

### Add Markdown and Bash KISS practice rules

New KISS practice files for Markdown (headings, formatting, tables, links, content organization) and Bash (script structure, quoting, variables, conditionals, pipelines, error handling). Detection heuristics table updated for *.md and *.sh file patterns.

## 0.9.20 — 2026-03-14

### Fix design recommendation truncation in terminal

Design exploration step now explicitly outputs the full recommendation as regular text before presenting the AskUserQuestion choice. Previously the recommendation could get stuffed into option descriptions which truncate in the terminal.

## 0.9.19 — 2026-03-14

### Add post-SHIP documentation polish step

New rnd-doc-polish skill checks and updates CLAUDE.md, README.md, project-specific docs, and stale inline comments after SHIP but before committing. Wired into start.md Phase 6 and quick.md Step 4.

## 0.9.18 — 2026-03-14

### Add project-specific code standards enforcement

New rnd-standards skill auto-extracts coding rules from CLAUDE.md files into regex-based slop patterns at pipeline start. The slop-gate hook now merges project-specific patterns from project-patterns.json alongside built-in patterns. Iron Law 5 in the builder skill mandates immediate self-correction on severity 3+ matches. Both /start and /quick commands now invoke rnd-standards during discovery. Five new tests cover all merging paths.

## 0.9.17 — 2026-03-14

### Fix stale docs in README and skill tables

Update README command table (12→14 commands, added review and audit), skill table (22→23 skills, added code-review), hash comment (6-char→8-char), command count comment (12→14), and structure trees (added validate.sh). Update using-rnd-framework skill table (added kiss-practices).

## 0.9.16 — 2026-03-14

### Add full codebase audit command

New /rnd-framework:audit command performs full codebase audits using multi-judge consensus. Unlike /review (diff-based), audit explores every tracked file against project standards auto-detected from CLAUDE.md files, KISS rules, and codebase conventions.

## 0.9.15 — 2026-03-14

### Suggest code review before committing in pipeline completion

## 0.9.14 — 2026-03-14

### Add evidence-based code review pipeline

New `/rnd-framework:review` command for reviewing code changes with the same multi-judge, evidence-based rigor as the verification pipeline. Supports three scope modes: uncommitted changes (default), commit ranges (`HEAD~3..HEAD`), and directory paths. Reuses the `rnd-verifier` agent — no new agents. Includes a `code-review` skill defining 6 review categories (architecture, security, correctness, testing, KISS compliance, style), 4 severity levels (critical, major, minor, info), and 3 verdicts (CLEAN, ISSUES_FOUND, CRITICAL_ISSUES). After review, suggests `/rnd-framework:start` or `:quick` to fix issues found. Checks: 212 → 218.

## 0.9.13 — 2026-03-14

### Add Tailwind KISS rules and update docs

## 0.9.12 — 2026-03-14

### Add Svelte and DuckDB KISS rules

## 0.9.11 — 2026-03-14

### Add KISS practices skill with language-specific rules

New `kiss-practices` skill with language-specific KISS (Keep It Simple) rules to prevent over-engineering. Includes general rules plus three language files: `elixir.md` (Elixir/Phoenix/Ecto), `javascript.md` (JS/TS/CSS/HTML), and `postgresql.md`. Phase 0 Discovery detects the project's tech stack and loads only the relevant language rules. Rules are overridable by project-local `kiss-practices` skills. All three agents (planner, builder, verifier) have KISS notes in their rules sections. Checks: 210 → 212.

## 0.9.10 — 2026-03-14

### Extract shared hook utilities into hooks/lib.sh

Consolidated duplicated patterns across 5 bash hook scripts (auto-allow-rnd, read-gate, prefer-tools, audit-log, session-start) into a shared `hooks/lib.sh` library. Provides: `hook_file_path()`, `hook_command()`, `hook_tool_name()` for JSON input parsing, `is_rnd_path()` for artifact path detection, `resolve_rnd_dir()` for session resolution, `hook_allow()` and `hook_block()` for PreToolUse decisions, and `PLUGIN_ROOT` path setup. Each hook now sources lib.sh instead of duplicating these patterns.

## 0.9.9 — 2026-03-14

### Remove hardcoded component counts from docs

## 0.9.8 — 2026-03-14

### Add colors, skill preloading, and disallowedTools to agents

All 5 agents now have distinct UI colors (planner: blue, builder: green, verifier: amber, integrator: purple, data-scientist: cyan), skill preloading via frontmatter (eliminating startup tool calls for skill loading), and the verifier has `disallowedTools: Write, Edit` as defense-in-depth alongside its tools allowlist. The `## Required Skills` sections in all agents updated to note skills are preloaded at startup. validate.sh extended with color, skills, and disallowedTools field validation. Checks: 199 → 210.

## 0.9.7 — 2026-03-14

### Add persistent memory to all agents

All 5 agents (planner, builder, verifier, integrator, data-scientist) now have `memory: user` frontmatter enabling persistent cross-project learning. Each agent includes a domain-specific `## Memory` section guiding what knowledge to accumulate: decomposition patterns (planner), debugging insights (builder), failure patterns (verifier), integration patterns (integrator), and data processing gotchas (data-scientist). The verifier's memory section explicitly preserves the information barrier by prohibiting storage of task-specific builder information. validate.sh extended with memory scope validation (user|project|local); 5 new tests. Checks: 194 → 199. Tests: 310 → 315.

## 0.9.6 — 2026-03-13

### Fix stale skill counts in CLAUDE.md and README

## 0.9.5 — 2026-03-13

### Add slop gate and fix confirmation prompts

New evidence-based PostToolUse hook (hooks/slop-gate) detects structural LLM anti-patterns in code written by Write/Edit tools. Includes: declarative pattern catalog (slop-patterns.json) with 15 anti-patterns, diff-aware analysis (Write analyzes full content, Edit analyzes only new_string), evidence-based scoring with PASS/WARN/FAIL verdicts, pipeline artifact integration (per-file reports and cumulative session scoring), companion skill (rnd-slop-detection) with 15 before/after remediation examples, hooks.json registration, validate.sh parity checks (193 total), and 70 new tests. Also fixes excessive confirmation prompts during pipeline runs by making the prefer-tools hook auto-allow all non-blocked bash commands instead of returning no-opinion. Skills: 20 to 21. Tests: 240 to 310.

## 0.9.4 — 2026-03-13

### Add /rnd-framework:resume command

New command that scans $RND_DIR artifacts to reconstruct pipeline state and continues a partially-completed pipeline from where it left off. Parses plan.md for task tree and waves, scans builds/, verifications/, and integration/ directories to determine per-task status, recreates TaskList entries, and presents next-action options via AskUserQuestion. Cross-session capable — works in a new Claude Code conversation. Commands: 11 → 12.

## 0.9.3 — 2026-03-12

### Add design exploration, failure modes, status codes, and tiered verification

Four superpowers-inspired features: Design Exploration phase (Phase 0.5) between Discovery and Planning, verification anti-pattern catalog (rnd-failure-modes skill), structured builder status codes (DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED), and two-stage verification with Correctness/Quality tiers. Updated agents, commands, skills, validate.sh parity checks, and tests.

## 0.9.2 — 2026-03-12

### Add optional tagging to bump command

## 0.9.1 — 2026-03-12

### Make verifier agent read-only

Remove Write tool from verifier agent, making it fully read-only. Adversarial test writing replaced with failure mode analysis (code inspection). Verifiers now return reports as text output; the orchestrator saves all verification report files. Updated across agent, skills (rnd-verification, rnd-multi-judge, rnd-debugging), commands (start, verify, quick), validate.sh parity descriptions, and README.

## 0.9.0 — 2026-03-11

### Add multi-judge verification and local expert discovery

Two new features for the pipeline. **Multi-judge verification** replaces the single-verifier model: two independent verifier agents check each task's output against pre-registered criteria, and a tiebreaker resolves split verdicts. The information barrier applies to all judges. New `rnd-multi-judge` skill defines the consensus protocol; `verify.md`, `start.md` Phase 3, `rnd-verification` skill, and `rnd-verifier` agent all updated. Quick mode retains single-verifier for lightweight tasks. **Local expert discovery** auto-scans the target project's `.claude/agents/` and `.claude/skills/` directories during Phase 0 (Discovery), reads frontmatter from each, and includes a structured summary in the Planner's context. The Planner can then reference project-local agents/skills in pre-registrations via an optional `Local expert` field. New `rnd-local-experts` skill defines the discovery protocol; `start.md` Phase 0, `rnd-planner` agent, and `rnd-decomposition` skill all updated. Plugin now has 18 skills and 155 validation checks.

## 0.8.5 — 2026-03-11

### Remove worktree isolation skill

## 0.8.4 — 2026-03-11

### Fix stale references and terminology

Updated doctor.md example version from v0.7.21 to v0.8.3, corrected skill count from 16 to 17 in CLAUDE.md, and standardized "info-barrier" to "information-barrier" across verify.md, rnd-verifier.md, and CHANGELOG.md to match established codebase terminology.

## 0.8.3 — 2026-03-11

### Add information-barrier pre-flight checks

Added defense-in-depth for the information barrier between Builder and Verifier agents. The verify command now runs a pre-flight sanity check that lists self-assessment files before prompt assembly and scans the assembled prompt for the substring `self-assessment`. The verifier agent now performs a startup self-check to detect leaked Builder reasoning in its prompt context. Updated the `bypassPermissions` documentation to describe all three defense layers (hook, pre-flight, self-check) instead of just documenting the weakness.

## 0.8.2 — 2026-03-11

### Harden hooks against edge cases

Improved resilience of three hook scripts: `audit-log` now guards against missing jq/date dependencies, uses `printf` instead of `echo` for POSIX correctness, silently exits on empty fields or malformed JSON, and handles write failures gracefully. `prefer-tools` fixes jq parse failure handling, improves echo/printf redirect detection by stripping `/dev/` paths before checking for redirects, and tightens the `.rnd` git-add pattern to avoid false positives. `read-gate` fixes jq parse failure handling and uses case-insensitive matching for self-assessment filenames. All changes paired with expanded test coverage.

## 0.8.1 — 2026-03-05

### Fix 30 code review findings

Comprehensive code review identified and fixed 30 issues across hooks, shell scripts, commands, agents, and skills. Key fixes: JSONL injection in audit-log (use jq -n), race condition in session creation (noclobber), semver validation in bump.sh, greedy cd-strip in prefer-tools, /dev/ exclusion for redirect detection, missing Write/Bash tools in planner agent, empty-argument handlers for build/integrate commands, prefer-system-tools restructured to lead with rg/fd/sd (blocked tools demoted to POSIX fallback), External dependencies field added to orchestration template, data-scientist role documented in using-rnd-framework, and RND_DIR path examples corrected to show session paths.

## 0.8.0 — 2026-03-05

### Remove team/swarm coordination from pipeline commands

Replaced TeamCreate/SendMessage/team_name team coordination with plain Agent tool calls in start.md. The Agent tool is blocking — agents run to completion and return results directly, making the team messaging layer unnecessary. This eliminates cross-session message leaks caused by Claude Code's experimental team feature. Phase 4 iteration now spawns a new Builder with feedback in the prompt instead of using SendMessage to a finished agent. TeamCreate and TeamDelete removed from validate.sh valid_tools list. All other command files (build, verify, integrate, quick) were already clean. Total checks: 147 (unchanged).

## 0.7.25 — 2026-03-05

### Add /rnd-framework:bump command for patch version automation

New `/rnd-framework:bump` command backed by `lib/bump.sh` automates the release version workflow. The shell script reads the current version from `plugin.json` via `jq`, increments the patch number, writes back atomically, prepends a correctly-formatted CHANGELOG entry, and stages both files. The command file handles argument parsing (headline + optional description via ` --- ` separator), prompts for the headline via `AskUserQuestion` when no arguments are provided, and asks for commit confirmation before creating the commit. New validation checks in `validate.sh` verify `lib/bump.sh` exists and is executable (total checks: 147). Commands: 10 → 11.

## 0.7.24 — 2026-03-05

### Fix agent spawn instructions using bare type names

All 6 command files (`start`, `plan`, `build`, `verify`, `integrate`, `quick`) used prose like "Spawn the `rnd-framework:rnd-planner` agent" to instruct agent spawning. The LLM sometimes stripped the `rnd-framework:` prefix when constructing the `subagent_type` parameter, causing `Agent type 'rnd-planner' not found` errors. Now all 11 spawn instructions use explicit parameter syntax: `subagent_type: "rnd-framework:rnd-planner"`, making the full qualified name unambiguous.

## 0.7.23 — 2026-03-05

### Add PostToolUse audit logging for Write and Edit operations

New `hooks/audit-log` PostToolUse hook records every file creation (Write) and modification (Edit) during active pipeline sessions. Each event is appended to `$RND_DIR/audit.jsonl` in JSONL format with timestamp, tool name, and file path. Silent when no pipeline session is active (no `$RND_DIR` set). A new PostToolUse section in `hooks.json` routes Write and Edit tool completions to the `audit-log` script.

## 0.7.22 — 2026-03-05

### Add /rnd-framework:doctor command for runtime environment diagnostics

New `/rnd-framework:doctor` command checks runtime readiness of the framework environment. Unlike `/rnd-framework:validate` (which checks static plugin structure — frontmatter, hooks, cross-references), `doctor` checks the live runtime state: presence and executability of CLI tools (`jq`, `bun`, `duckdb`), hook scripts, RND_DIR accessibility and write permissions, marketplace registration, plugin version sync between source and cache, and Julia MCP availability. Reports PASS/FAIL per check with a summary. Use `validate` to check plugin integrity after edits; use `doctor` when something isn't working at runtime.

## 0.7.21 — 2026-03-04

### Add DuckDB CLI as dual-tool option to rnd-data-science skill and rnd-data-scientist agent

The `rnd-data-science` skill and `rnd-data-scientist` agent previously relied solely on Julia (via `mcp__julia__julia_eval`) as the computation backend. DuckDB CLI is now a first-class alternative for tasks that are better suited to SQL: querying CSV/Parquet files, aggregating large datasets, and ad-hoc relational analysis. The skill's tool-selection heuristic guides the agent to choose between Julia (numerical computation, Plots.jl charts, matrix ops) and DuckDB (SQL queries, file ingestion, tabular aggregation) based on task type. Both tools remain available in the same agent session. Reference docs updated in `using-rnd-framework` skill table, README agent table, and CLAUDE.md agent table.

## 0.7.20 — 2026-03-04

### Add rnd-data-scientist agent and rnd-data-science skill

New standalone specialist agent (`rnd-data-scientist`, opus) for numerical and analytical work — finances, calculations, data wiring, analytics, tables, CSV/XLS, charts, and insights. Unlike the 4 pipeline-phase agents, this agent is called on-demand by the orchestrator or other agents when a task involves data work. Uses Julia MCP tools (`mcp__julia__julia_eval`) as primary computation environment, loaded via `ToolSearch` at runtime.

Companion `rnd-data-science` skill provides structured methodology: data validation, numerical verification (cross-checks, tolerance-based comparison), CSV/XLS ingestion, financial calculations, chart generation (Plots.jl), and insight extraction. Four content-parity entries added to `validate.sh` ensuring skill-agent alignment. All reference docs updated (README, `using-rnd-framework`, CLAUDE.md). Total checks: 122 → 135. Agents: 4 → 5. Skills: 16 → 17.

## 0.7.19 — 2026-03-04

### Add skill-agent content parity checks to validate.sh

`/rnd-framework:validate` now checks that key content markers in skill files also appear in their corresponding agent mirrors. A data-driven parity table defines 6 marker-pairs across 3 skill-agent pairs (rnd-decomposition↔rnd-planner, rnd-building↔rnd-builder, rnd-verification↔rnd-verifier). Adding a new parity check requires one array entry — no new bash logic. Total checks: 116 → 122.

## 0.7.18 — 2026-03-04

### Add external dependency verification to pipeline

External systems (DB schemas, API contracts, file formats, env vars, third-party services) had no first-class representation in the pipeline. A Builder could write code against a wrongly-assumed schema, and the Verifier had no hook to catch it — tests would pass because both the code and the mocks shared the same wrong assumptions.

Now all three pipeline phases enforce external dependency awareness:

- **Planner** (`rnd-decomposition` skill + `rnd-planner` agent): Pre-registration template gains an `External dependencies` field with sub-structure (`system`, `contract`, `verification`). New decomposition heuristic triggers Phase 0 spikes for unverified external contracts. Checklist item enforces field presence.
- **Builder** (`rnd-building` skill + `rnd-builder` agent): New step 2.5 "Verify External Dependencies" requires querying/reading actual external systems before writing code. Evidence recorded in build manifest. Self-assessment template restructured to distinguish verified from unverified external assumptions.
- **Verifier** (`rnd-verification` skill + `rnd-verifier` agent): Adversarial testing gains "External contract conformance" category. Code inspection gains check for hardcoded unverified assumptions. Cross-criterion sweep gains "External assumption probe" — flags all dependent criteria as at-risk when build manifest lacks verification evidence.

## 0.7.17 — 2026-03-04

### Distinguish FAIL from NEEDS ITERATION in verify and start commands

Previously both `verify.md` and `start.md` treated FAIL and NEEDS ITERATION identically ("FAIL: Same as NEEDS ITERATION"), routing both to the Builder for iteration. The `rnd-verification` skill defines them differently: NEEDS ITERATION is "all-but-one criteria met with a clear, isolated fix path" while FAIL is "any criterion unmet without a clear fix path." Now FAIL routes to re-planning (not iteration), and in auto-continue mode, FAIL always pauses for user decision — it is an escalation gate.

## 0.7.16 — 2026-03-04

### Add summary table and --quiet mode to validate.sh

`/rnd-framework:validate` now outputs a per-category summary table at the end showing pass/fail counts for Manifest, Hooks, Skills, Agents, Commands, Output Styles, and Cross-References. New `--quiet` flag suppresses individual check lines and shows only the summary table — useful for CI. Also fixed a `grep -c || echo "0"` bug where both grep's stdout (`"0"`) and echo's stdout (`"0"`) were captured in command substitution, producing `"0\n0"` and failing integer comparison.

## 0.7.15 — 2026-03-04

### Define skip procedure for failing tasks

The "Skip and continue" option in `start.md` and `verify.md` had no defined mechanism: no task status mapping, no dependency handling, no integrator guidance. Added a **Skip Procedure** section to both commands that specifies: (1) mark with `metadata: {"skipped": true, "reason": "..."}` and `completed` status, (2) check downstream dependencies and warn about dependent tasks, (3) inform the integrator which tasks were skipped. Phase 5 now reads "all non-skipped tasks" instead of "ALL tasks."

## 0.7.14 — 2026-03-04

### Increase artifact path hash from 6 to 8 characters

The project slug hash in `rnd-dir.sh` used 6 hex characters (~16M unique values). With many local projects, hash collisions could silently merge artifact directories. Increased to 8 hex characters (~4B unique values). The `cksum` fallback format string was also widened (`%06x` → `%08x`). **Breaking:** existing sessions under 6-char paths are preserved on disk but won't be discovered; run `/rnd-framework:history` to find old artifacts manually.

## 0.7.13 — 2026-03-04

### Expand valid agent tool list in validate.sh

The agent tool validation only recognized 12 tools (`Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep`, `NotebookRead`, `NotebookEdit`, `WebFetch`, `WebSearch`, `Agent`, `TodoWrite`). Added 12 more: `AskUserQuestion`, `TaskCreate`, `TaskGet`, `TaskUpdate`, `TaskList`, `Skill`, `SendMessage`, `TeamCreate`, `TeamDelete`, `EnterPlanMode`, `ExitPlanMode`, `EnterWorktree`, `ToolSearch`. This prevents false "unknown tool" failures when agents are given orchestration or team-coordination tools.

## 0.7.12 — 2026-03-04

### Use generic path templates in artifact layout examples

README artifact path examples used concrete values (`myproject-6f015c`, `20260303-102051-4b5f`) that could mislead users about the actual slug format. Replaced with generic templates (`<dirname>-<hash>`, `<YYYYMMDD-HHMMSS-XXXX>`) matching the inline helper description. CLAUDE.md was already fixed in 0.7.10.

## 0.7.11 — 2026-03-04

### Add argument-hint validation to validate.sh

`/rnd-framework:validate` now checks that commands using `$ARGUMENTS` have an `argument-hint` frontmatter field, and that commands with `argument-hint` actually reference `$ARGUMENTS`. Catches missing usage hints on new commands. Adds 6 checks (116 total). Required `|| true` guard on the `frontmatter_val` call since `argument-hint` is optional — without it, `set -euo pipefail` kills the script when `grep` finds no match inside the function's pipeline.

## 0.7.10 — 2026-03-04

### Add /validate to command tables and fix artifact path examples

The `/rnd-framework:validate` command was missing from both the README and `using-rnd-framework` skill command tables (only 8 of 9 commands listed). Also fixed the artifact path example in README and CLAUDE.md: slug format was shown as `project-<hash>` but the actual format is `<dirname>-<hash>` (computed from the project directory's basename).

## 0.7.9 — 2026-03-04

### Add cross-reference validation to validate.sh

`/rnd-framework:validate` now checks 33 cross-references in addition to the 77 structural checks: skill references in the `using-rnd-framework` table (15), skill references in agent "Required Skills" sections (9), and agent references in command spawn instructions (9). Distinguishes skill refs (backtick-wrapped) from command refs (slash-prefixed) to avoid false positives.

## 0.7.8 — 2026-03-04

### Warn on stale plugin cache in session-start

The `session-start` hook now detects version mismatches between the cached plugin and the source repo. When running in the plugin's source repository, it compares the cached `plugin.json` version against the source version. If they differ, a warning appears in the session context suggesting `/plugin update`. Searches multiple common repo layouts (`plugins/rnd-framework/`, `rnd-framework/`, root-level).

## 0.7.7 — 2026-03-04

### Block project file writes during planning phase

Three-layer defense preventing the Planner from modifying project files: (1) agent frontmatter restricts tools to Read/Grep/Glob, (2) explicit "NEVER modify project files" instruction as first rule, (3) `auto-allow-rnd` hook blocks non-`.rnd/` Write/Edit calls when a `.planning-phase` marker file exists in `$RND_DIR`. The orchestrator creates the marker before spawning the planner and removes it after. `.rnd/` writes (plan.md) remain allowed.

## 0.7.6 — 2026-03-04

### Add plugin validation command

New `/rnd-framework:validate` command runs `lib/validate.sh` to check plugin structure without starting a new session. Validates: plugin manifest (JSON, semver), hooks (JSON, script existence and executability), skills (frontmatter, name/directory consistency), agents (frontmatter, valid tools and models), commands (frontmatter), and output styles (frontmatter). Reports PASS/FAIL per check with a summary count. 77 checks across all 6 artifact types.

## 0.7.5 — 2026-03-04

### Harden hook system with external scripts and jq

Extracted all inline PreToolUse hooks from `hooks.json` into external scripts: `auto-allow-rnd` (shared by Write and Edit matchers) and `read-gate` (Read matcher with information barrier). Added echo/printf file redirect blocking to `prefer-tools` — catches `echo/printf ... > file` patterns while allowing `>&2` stderr output. Replaced the fragile `escape_for_json()` bash function in `session-start` with `jq -n --arg`, eliminating manual string escaping that missed control characters and unicode edge cases.

## 0.7.4 — 2026-03-03

### Namespace agent references in commands and skills

All commands and skills referenced agents by short name (e.g., `rnd-planner`), but Claude Code's plugin system requires the full `plugin:agent` namespace (`rnd-framework:rnd-planner`). This caused "Agent type not found" errors whenever the pipeline tried to spawn an agent. Updated all 14 spawn instructions across 6 commands, 2 skills, and the README to use the full namespace. Agent frontmatter `name:` fields remain unchanged.

## 0.7.3 — 2026-03-03

### Remove unused skills-core.js

`lib/skills-core.js` was an ESM module implementing skill discovery (frontmatter parsing, recursive directory search, name resolution with shadowing). None of its exports were imported by any hook, command, agent, or script — Claude Code's native plugin system handles skill discovery by directory convention. Deleted the file and removed all references from README.md and CLAUDE.md.

## 0.7.2 — 2026-03-03

### Update documentation with marketplace install and fix stale content

Root README now covers marketplace-based installation, plugin updates, and auto-update configuration instead of the old `--dir` flag. rnd-framework README and CLAUDE.md synced with current codebase: 8 commands (added `/rnd-framework:history`), 16 skills, `prefer-tools` hook, `rnd-dir.sh` helper, and session-based artifact layout.

## 0.7.1 — 2026-03-03

### Use hookSpecificOutput format in PreToolUse hooks

All PreToolUse hooks were outputting `{"decision": "allow/block"}` — a format Claude Code doesn't recognize for PreToolUse events. This caused "PreToolUse:Bash hook error" messages and auto-allow rules failing silently, falling through to permission prompts.

Allow decisions now output `hookSpecificOutput` JSON with `permissionDecision: "allow"`. Block decisions now use `exit 2` with the reason on stderr. Unmatched commands exit 0 with no output (no opinion). Applied to all 4 PreToolUse hooks: Write, Edit, Read (inline in `hooks.json`), and Bash (`prefer-tools` script).

## 0.7.0 — 2026-03-03

### Fix all PreToolUse hooks to read tool input from stdin

All hooks were reading `$TOOL_INPUT` (an environment variable that Claude Code never populates). Tool input is actually passed as JSON on stdin. This caused every auto-allow rule to silently fail — `rnd-dir.sh`, `.rnd/` paths, `ls`, and the information barrier for self-assessment files all prompted for permission instead of resolving automatically. The `prefer-tools` hook also failed to block `sed`/`cat`/`grep`/`find` since it couldn't see the command.

All hooks now use `jq` to parse stdin JSON. The `prefer-tools` script additionally strips `cd` prefixes with `sed` instead of a complex regex, and matches the actual extracted command string rather than raw JSON.

## 0.6.1 — 2026-03-03

### Structured next-step options after task completion

The `using-rnd-framework` skill now requires `AskUserQuestion` after completing any user request — not just at pipeline decision points. Previously the agent would end with plain text like "Done." after finishing ad-hoc tasks. Now it always presents structured options: continue with related work, review changes, or finish the session.

## 0.6.0 — 2026-03-03

### Structured task input for no-args invocations

`/rnd-framework:start`, `/rnd-framework:quick`, and `/rnd-framework:plan` now handle empty arguments with `AskUserQuestion` instead of falling back to plain text. When invoked without a task description, the orchestrator scans the codebase (recent commits, TODOs, recent changes) and presents 2-4 concrete task suggestions as structured options. This follows the framework's own mandatory rule that every decision point uses `AskUserQuestion`.

## 0.5.3 — 2026-03-01

### Handle cd-prefixed commands in Bash hook

The `prefer-tools` hook now correctly matches commands prefixed with `cd /path &&` or `cd /path ;`. Previously, `cd /path && sed ...` bypassed the block and `cd /path && ls` bypassed the auto-allow because the regex anchored to the start of the command string.

## 0.5.2 — 2026-03-01

### Auto-allow ls in Bash hook

The `prefer-tools` hook now auto-allows `ls` commands without prompting for confirmation. `ls` is read-only and safe, and is frequently used during pipeline operations to inspect directory structure.

## 0.5.1 — 2026-03-01

### Auto-allow rnd-dir.sh in Bash hook

The `prefer-tools` PreToolUse hook now auto-allows Bash commands containing `rnd-dir.sh`. Previously, running `rnd-dir.sh -c` to create the artifacts directory prompted for user confirmation because the script's path (`plugins/cache/.../lib/rnd-dir.sh`) doesn't contain `.rnd/` — only its output directory does.

## 0.5.0 — 2026-03-01

### Session-based history

Each pipeline run now gets a unique session ID (`YYYYMMDD-HHMMSS-XXXX`) stored in `<base>/.current-session`. Artifacts are written to `<base>/sessions/<session-id>/` instead of the project base directory, preserving history across runs. `rnd-dir.sh` gains `--finish` (clear session ID) and `--base` (output project base dir) flags. New `/rnd-framework:history` command lists past sessions with dates, task names, and SHIP/NO-SHIP verdicts. Completion flow offers "Finish session" alongside existing cleanup options.

## 0.4.1 — 2026-03-01

### Autonomous agents

All pipeline agents (Planner, Builder, Verifier, Integrator) are now spawned with `mode: "bypassPermissions"`. This eliminates permission prompts during pipeline execution — the framework's own quality gates (pre-registration, information barriers, independent verification) provide sufficient control. Applied across all 7 commands (`start`, `plan`, `build`, `verify`, `integrate`, `quick`, `status`) and documented in the orchestration skill.

## 0.4.0 — 2026-03-01

### Iteration convergence

Verifier now reports ALL issues in a single pass (exhaustive reporting discipline with cross-criterion sweep), and Builder now fixes ALL failed criteria in one iteration (convergent iteration with shared code path checks). Eliminates the "whack-a-mole" pattern where issues surfaced incrementally across rounds.

### Auto-continue mode

New "Approve plan and auto-continue" option at plan approval. Skips happy-path user gates (post-build, post-verify PASS, post-verify ITERATE, post-integrate SHIP) while preserving escalation gates (budget exhaustion, NO-SHIP, final completion). Opt-in, token-aware.

### Phase 0: Discovery

Before the Planner decomposes a task, the orchestrator now explores the codebase, identifies ambiguities, and asks 3-5 targeted clarifying questions. Discovery context (codebase findings, user answers, constraints) is passed to the Planner to inform decomposition. Skippable when the task is already highly specific.

## 0.3.1 — 2026-03-01

### Config directory resolution fix

`rnd-dir.sh` now checks `CLAUDE_CONFIG_DIR` before falling back to `~/.claude`. Previously, custom Claude profiles (e.g., `claude-personal` using `~/.claude-personal`) would incorrectly place artifacts under `~/.claude/.rnd/` because `CLAUDE_PLUGIN_ROOT` isn't available in the Bash tool's shell environment.

## 0.3.0 — 2026-03-01

### Centralized artifacts

Pipeline artifacts (plans, build manifests, verification reports) now live in `<claude-config-dir>/.rnd/<project-slug>/` instead of `.rnd/` inside the user's project. No `.gitignore` entry needed. The `lib/rnd-dir.sh` helper computes the path from `$CLAUDE_PLUGIN_ROOT` (falling back to `~/.claude`); all commands, agents, and skills reference it via `$RND_DIR`.

### User decision gates

Every pipeline command now uses `AskUserQuestion` with structured options at decision points. Previously, standalone commands (`/plan`, `/build`, `/verify`, `/integrate`, `/status`) ended without prompting the user for next steps.

### Agent communication contracts

All four agents (Planner, Builder, Verifier, Integrator) now have explicit `SendMessage` contracts: they notify the orchestrator on start, completion, approach disagreements, and blockers. Agents never finish work silently.

### Tool discipline

- Agents must use `Write`/`Edit` tools instead of bash heredocs for file creation
- Agents must use `Read`/`Grep`/`Glob` instead of `cat`/`grep`/`find` in Bash
- Agents must not use `sleep` or polling loops — the Agent tool is blocking
- PreToolUse hook blocks `git add .rnd/` and auto-allows operations on `$RND_DIR` paths

### New skills

- **prefer-system-tools** — prefer system CLI tools, then Bun scripts, then Python
- **bun-scripting** — prefer Bun over Python for scripting tasks
- **committing** — git commit message conventions and pre-commit confirmation

### Output styles

Three custom output styles: `scientific`, `rigorous`, and `pipeline`.

### Information barrier enforcement

PreToolUse hook blocks Verifier agents from reading Builder self-assessment files, preventing anchoring bias during independent verification.

## 0.2.0 — 2026-02-28

Initial release.

- 4 specialized agents: Planner (opus), Builder (sonnet), Verifier (opus), Integrator (sonnet)
- 7 slash commands: `/start`, `/plan`, `/build`, `/verify`, `/integrate`, `/status`, `/quick`
- 15 skills covering decomposition, building, verification, iteration, integration, isolation, debugging, scheduling, scaling, completion, and orchestration
- Pre-registration documents with testable success criteria
- Dependency matrix and wave-based parallel execution
- Information barriers between Builder and Verifier
- Iteration budgets with escalation paths
- Session bootstrap via `SessionStart` hook