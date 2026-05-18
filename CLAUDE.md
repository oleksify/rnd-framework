# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing **rnd-framework** — a scientific-method orchestration system for structured coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition. Uses a multi-agent execution model: 11 specialized agents with structural isolation enforce the information barrier at the context-window level.

The plugin lives under `plugins/rnd-framework/`. The root `.claude-plugin/marketplace.json` is a local plugin registry. Plugins can also be declared inline in `settings.json` using `source: 'settings'` (v2.1.80+).

## Repository Layout

```
lib/plugin-dir-base.sh                  # Canonical shared artifact-dir logic (each plugin keeps its own copy for cache compat)

plugins/rnd-framework/
├── .claude-plugin/plugin.json          # Plugin manifest
├── agents/                             # 11 specialized pipeline agents
├── commands/                           # /rnd-framework:* slash commands
├── skills/                             # One dir per skill, each with SKILL.md
├── cards/<role>/<lang>/CARD-<ID>.md    # Flash-card priming corpus (~119 cards, v2.5): canon principles → language tiers → library tiers, with optional `specializes:` parent refs. Five canon principles: P-IMPOSSIBLE-01, P-EFFECTS-EDGE-01, P-SMALL-MODULES-01, P-PURE-RENDER-01, P-MEASURE-01. Python library tier: FastAPI (FAS*), Pydantic v2 (PYD*), SQLAlchemy 2 (SQA*), Django ORM (DJG*), asyncio (AIO*), httpx (HTX1), Celery (CEL1), Flask (FLA1). Roles: planner, builder, reality-auditor, verifier, cleanup. Format gold standard enforced by `tests/cards-corpus-lint.test.sh` (strict-by-default; 6-field frontmatter + sentence-form `scope:` + id/role/language-vs-dir match + no `### ` body headings)
├── output-styles/                      # scientific, rigorous, pipeline
├── hooks/
│   ├── hooks.json                      # Routes Session/Setup/InstructionsLoaded/Pre+PostToolUse/Pre+PostCompact/StopFailure/Cwd+FileChanged/TaskCreated/Subagent*/PermissionDenied/Worktree*
│   ├── lib.sh                          # Shared bash utils: input parsing, path predicates, decision output (incl. defer), cmd_hash
│   ├── read-gate.sh / write-gate.sh / glob-grep-gate.sh / bash-gate.sh   # Info barrier + tool discipline + .rnd/ auto-allow
│   ├── session-start.sh / session-end.sh / pre-compact.sh / post-compact.sh
│   ├── post-dispatch.sh                # Write/Edit audit + Bash output cache writer + ≥50-line advisory
│   ├── stop-failure.sh / setup.sh / instructions-loaded.sh / permission-denied.sh
│   ├── cwd-changed.sh / file-changed.sh / task-created.sh / subagent-lifecycle.sh
│   ├── format-on-save.sh / session-title.sh
│   ├── builder-dismissal-gate.sh / coverage-gaps-gate.sh / anomaly-gate.sh / verifier-case-gate.sh / cleanup-bloat-gate.sh / drift-report-gate.sh   # SubagentStop quality gates (agent-scoped)
│   ├── stop-condition-revisions.sh     # PreToolUse Write|Edit: halts when same path is rewritten ≥ RND_STOP_FILE_REVISIONS times (default 5)
│   ├── evidence-pack-gate.sh           # PreToolUse Read: validates evidence-pack manifest schema for verifier
│   ├── worktree-create.sh / worktree-remove.sh
│   └── statusline.sh                   # Rate-limit % + pipeline phase + worktree indicator
├── lib/
│   ├── rnd-dir.sh                      # $RND_DIR resolver and session manager (flags: -c, --finish, --base, --roadmap, --facts, --calibration)
│   ├── plugin-dir-base.sh              # Local copy of shared artifact-dir logic
│   ├── bump.sh / validate.sh / validate-xrefs.sh
│   ├── tools.json                      # Heavy-tool registry (pytest/jest/vitest/tsc/eslint/dialyzer/mypy/bun/cargo/mix/ruff/biome) with relevant_globs for input scoping; project override at $RND_DIR/tools.json
│   ├── run-tool.sh                     # Evidence-pack writer (opt-in: RND_EVIDENCE_PACK=1)
│   ├── manifest-schema.json            # JSON Schema for evidence-pack manifest; `x-disallowed-fields` is the SSOT consumed by evidence-pack-gate.sh
│   ├── audit-event.sh                  # Single-line {event,task_id,tool,timestamp} emitter to $RND_DIR/audit.jsonl
│   ├── audit-scan.sh                   # Subcommands: `revisions <task> <path>`, `verdict_history <task>` (prints FLIP_DETECTED on PASS/FAIL/PASS or FAIL/PASS/FAIL)
│   ├── rnd-undo.sh                     # Surgical task-scoped revert (reads `## Files written` from build manifest)
│   ├── card-retrieve.sh                # Deterministic tag-overlap card retrieval (--role, --task-type, --tags, --max)
│   ├── rnd-cards-propose.sh            # Cluster FAIL feedback in calibration.jsonl → draft card scaffolds (4-gram Jaccard)
│   ├── rnd-cards-impact.sh             # Compare iterations-to-PASS pre/post a --since rollout date per task_type
│   └── calibration.sh                  # Auto-escalation helpers; subcommands: window, false_pass_rate, should_promote, promote_tier, task_type_window
├── proofs/                             # Lean 4 formal verification of pipeline invariants
└── README.md
```

## Architecture

### Execution Model

Eleven specialized agents handle each pipeline phase in isolated context windows. The orchestrator dispatches work to agents, enforcing structural information barriers — the Verifier literally cannot see the Builder's reasoning because they run in separate context windows.

| Phase | Agent | Purpose |
|---|---|---|
| Planning | `rnd-planner` (opus/high, adaptive) | Decomposes tasks into pre-registered sub-tasks with testable criteria; capped at max 4 tasks/wave with min 1-hour scope and forced coalescing; emits `Heuristic ceiling: <integer>` meta-field in plan.md (consumed by the plan-size stop condition: halt when `task_count > RND_STOP_PLAN_RATIO * ceiling`, default ratio 1.5); pre-registrations include a required `## Assumptions` section (`Assumption: ... Refuted by: ...`, placeholder `- None` when none) — the Verifier downgrades a verdict by one tier and emits `gateFired: {gate: "assumption_unchecked"}` when an Assumption's Refuted-by action was declared but not executed |
| Building | `rnd-builder` (sonnet/high, adaptive, worktree) | Implements tasks using TDD; produces build manifest + self-assessment |
| Reality Audit | `rnd-reality-auditor` (sonnet/low) | Per-task audit of declared external references (URLs, APIs, schemas, env vars, data); only runs when the task declares `External dependencies`; runs an "Existence Pre-Pass" Step 0 (mechanical probes — file-execution only, no `python -c`/`node -e`/`bun -e`) that verifies every imported module / third-party method call / RFC or error-code citation / env-var name actually exists in the form claimed, before adversarial experiments; MISSING short-circuits to `INVALID_FOUND` and emits a `FALSE_PASS_PROXY` calibration record if a prior Builder PASS exists for the task |
| Proof Gate | `rnd-proof-gate` (sonnet/low) | Formal Lean 4 proofs of pre-registration criteria (advisory); only runs when the task has `Proof: lean` and Lean is on PATH; amendments to proven criteria force a re-prove before re-verification |
| Verification | `rnd-verifier` (sonnet/high, adaptive, worktree) | Wave-batched: one spawn per wave reviews all task pre-regs and emits a per-task verdict map; writes `T<id>-verification.md` full prose report for every verdict (PASS, FAIL, NEEDS_ITERATION, PASS_QUALITY_NEEDS_ITERATION, AMEND_REQUIRED) with a required `## Coverage Gaps` section (`Checked:` + `Couldn't check:` sub-bullets — enforced by `coverage-gaps-gate.sh`); AMEND_REQUIRED (cited concrete spec defect required; routes to amendment arbiter; clean-slate re-verification afterward) pauses the task without blocking the wave; information barrier enforced; HIGH criticality routes through wave-batched multi-judge with verdict-based escalation gate (only FAIL/NEEDS_ITERATION/PASS_QUALITY_NEEDS_ITERATION/AMEND_REQUIRED escalates to full dual-judge; `RND_MULTI_JUDGE_ALWAYS=1` restores always-dual-judge) |
| Amendment | `rnd-amendment-arbiter` (opus/xhigh, non-adaptive) | Evaluates AMEND_REQUIRED verdicts; proposes spec corrections (AMEND), recommends rebuild (REBUILD), or routes to Planner re-plan (ESCALATE_REPLAN); inputs strictly limited to original pre-reg + Verifier verdict |
| Cleanup | `rnd-cleanup` (sonnet/medium, worktree) | Per-task dead-code sweep after Verifier PASS; detects dead functions, orphan files, duplicate implementations, stale comments; applies fixes and rolls back if cleanup breaks re-verification |
| Polish | `rnd-polisher` (opus/high, non-adaptive, per-wave, worktree) | Wave-level cross-task seam fixer: detects cross-task duplication, naming and API drift, helpers that should be lifted to shared locations, and structural inconsistencies; runs after all per-task cleanup; rolls back if re-verification breaks; reports to `$RND_DIR/polish/wave-<N>-polish-report.md` |
| Integration | `rnd-integrator` (haiku/low) | Merges verified outputs, runs integration/system tests |
| Debugging | `rnd-debugger` (sonnet/high, adaptive, worktree) | Root cause analysis for failing tasks |
| Data Science | `rnd-data-scientist` (sonnet/medium) | Standalone specialist for numerical/analytical work |
| Drift detection | `rnd-drift-detector` (sonnet/medium) | Per-wave drift analysis between Builder and Verifier; reads plan.md, Builder manifests, and audit.jsonl; emits a structured drift report to `$RND_DIR/drift/`; report schema enforced by `drift-report-gate.sh` |

**Dispatch Policy (criticality-driven, per-agent):** the orchestrator overrides the spawned agent's model based on the per-task `Criticality` field. The mapping is per-agent, not a single global table:

| Agent | LOW | MEDIUM | HIGH |
|---|---|---|---|
| `rnd-planner` | opus/high | opus/high | opus/xhigh |
| `rnd-verifier` | sonnet/high | opus/high | opus/xhigh |
| `rnd-builder` | sonnet/high | sonnet/high | opus/high |
| `rnd-debugger` | sonnet/high | sonnet/high | opus/high |
| `rnd-amendment-arbiter` (non-adaptive) | opus/xhigh | opus/xhigh | opus/xhigh |
| `rnd-polisher` (non-adaptive, per-wave) | opus/high | opus/high | opus/xhigh |

If `Criticality` is absent (or no pre-reg exists), the orchestrator does NOT override and the agent's frontmatter `model:` is used. Effort is NOT per-spawn overridable; it stays at the agent's frontmatter value. Non-adaptive agents always run at their listed model regardless of criticality. Full policy lives in the `rnd-framework:rnd-orchestration` skill.

### Information Barrier and Permission Hooks

The `hooks.json` routes each event to an external script under `hooks/`. The load-bearing policies:

- **Information barrier** (`read-gate.sh`, `glob-grep-gate.sh`, `bash-gate.sh`): blocks any tool call where the path or command string contains `self-assessment`, OR matches `.rnd/.*briefs/`, OR matches `.rnd/.*cleanup/` — when the agent is `rnd-verifier`, `rnd-proof-gate`, or has no agent_type. The `.rnd/` artifact-root anchor on the `/briefs/` and `/cleanup/` patterns is load-bearing: it distinguishes genuine artifact-tree paths from the same-named corpus directories (`cards/cleanup/`) and project source. Prevents verification/proof phases from anchoring on build- or cleanup-phase reasoning. `glob-grep-gate.sh` additionally checks the concatenation of `path` + `pattern` so a split like `path=/.../.rnd/sessions/x` + `pattern=/cleanup/*.md` cannot smuggle a barrier-protected glob through. The proof-gate inclusion matches the Lean theorem `proofGate_cannot_access_self_assessment` in `proofs/InformationBarrier.lean`.
- **Auto-allow `.rnd/` and plugin cache** (`read-gate.sh`, `write-gate.sh`, `bash-gate.sh`, `glob-grep-gate.sh`, `settings.json`): Read/Write/Edit/Glob/Grep on `.rnd/` artifact paths auto-allowed. For Bash, `.rnd/` auto-allow fires only AFTER tool-discipline segment checks pass (so sed and inline interpreters are still blocked even when a `.rnd/` path appears). `read-gate.sh` also auto-allows `plugins/cache/` (skills, agents) and `$CLAUDE_CONFIG_DIR/learnings/` (cross-session knowledge).
- **Worktree topology** (write-side agents only): the five write-side adaptive agents — `rnd-builder`, `rnd-verifier`, `rnd-cleanup`, `rnd-polisher`, `rnd-debugger` — declare `isolation: "worktree"` and spawn into per-task git worktrees at `.rnd-worktrees/<session>/T<id>/` on ephemeral branches `rnd/<session>/T<id>`. Read-side agents (`rnd-planner`, `rnd-integrator`) run in the main checkout. `$RND_DIR` lives under `~/.claude/.rnd/` — entirely OUTSIDE any worktree — so manifests, evidence packs, verifications, briefs, and `audit.jsonl` remain readable across all agents; the information barrier is enforced by hooks, not filesystem topology. Only the project source tree is per-agent scoped. The `rnd-integrator` is the sole merge path back to main: fetch each verified task's branch, `git merge --no-ff` in pre-reg dependency order, then prune branches and worktrees.
- **Tool discipline** (`bash-gate.sh`): blocks `sed`, `awk`, `echo`/`printf` with file redirects, inline interpreters (`python -c`, `node -e`, `bun -e`, bare interpreter as pipe target), shell loops (`for`/`while`/`until`), and `/tmp/` redirects — enforces dedicated Claude Code tools and `$RND_DIR` for temp storage. Read-side commands (`cat`, `head`, `tail`, `grep`, `rg`, `find`) pass through. Splits compound commands (`&&`/`||`/`;`/`|`/`$(...)`/backticks) and strips env-var prefixes (`FOO=bar cmd`) before checking each segment. File execution (`python file.py`, `bun test`, `python -m pytest`) is allowed. Also handles commit protection: blocks `git add` of `.rnd/` and emits an advisory on `git push` to main/master/production.
- **Audit + Bash output cache** (`post-dispatch.sh`): logs Write/Edit ops to `$RND_DIR/audit.jsonl`, advises when output >50 lines, and writes Bash stdout/stderr to `$session/.bash-cache/<sha>.txt` keyed by `cmd_hash` from `lib.sh`. PreToolUse Bash detects identical re-runs within `RND_BASH_CACHE_TTL_SECONDS` (default 600) and points at the cached file when the prior output was ≥10 lines. Non-blocking; cache auto-clears with session.
- **Stop conditions** (`stop-condition-revisions.sh`): PreToolUse Write|Edit halts when the same path has been rewritten `RND_STOP_FILE_REVISIONS` times (default 5) for the active task — via `lib/audit-scan.sh revisions`. The verdict-flip and plan-size stop conditions are enforced at the orchestration-prompt level (gate names `stop_condition_verdict_flip`, `stop_condition_plan_size`), invoke `AskUserQuestion`, and emit `gateFired` audit events.
- **SubagentStop quality gates** (agent-scoped): blocking — `builder-dismissal-gate.sh` (phrases like `pre-existing`/`out of scope` blocked; the only legal dismissal path is a `T<id>-found-issues.jsonl` ledger entry with `decision:"escalated"`); `coverage-gaps-gate.sh` (verification.md must have substantive `## Coverage Gaps`); `verifier-case-gate.sh` (must have substantive `## Case for PASS` and `## Case for FAIL` — symmetry forces opposing-side articulation); `anomaly-gate.sh` (reality-report must have sourced `## Anomalies` OR substantive `## No-Finding Rationale` ≥200 chars); `drift-report-gate.sh` (drift report must have `## Drift Hypothesis` + `## Counter-evidence` + `## Verdict` with value in `NO_DRIFT|MINOR_DRIFT|MAJOR_DRIFT|RESET_RECOMMENDED`). Advisory-only — `cleanup-bloat-gate.sh` emits `bloat_aversion_underperform` when cleanup deletion ratio <15%. Every block emits a `gate_fired` (or `gateFired`) audit event.
- **Evidence pack gate** (`evidence-pack-gate.sh`): PreToolUse Read; runs the info-barrier check first, then — only for `rnd-verifier` reading `$RND_DIR/evidence/T*/manifest.json` — validates the manifest by `jq has()` against `lib/manifest-schema.json`'s `x-disallowed-fields` (default: `notes`, `summary`, `confidence`, `reasoning`, `explanation`). Blocks with `EVIDENCE PACK BARRIER` on any disallowed field.
- **Other** observability/UX hooks: `stop-failure.sh` (API-error logging), `permission-denied.sh` (auto-mode denial → `{retry: true}`), `cwd-changed.sh` (cross-repo warning), `file-changed.sh` (external `.rnd/` edit advisory), `task-created.sh`, `subagent-lifecycle.sh`, `worktree-create.sh`/`worktree-remove.sh`, `format-on-save.sh` (auto-format code on Write/Edit; cached detection; skips `.rnd/`), `session-title.sh` (dynamic `RND: <phase> | <project>` title for `/resume`).

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

Notable skills: `rnd-roadmapping` (roadmap.md format + milestone lifecycle), `rnd-learning` (auto-capture pipeline gotchas to `$CLAUDE_CONFIG_DIR/learnings/`), `rnd-formatting` (detect+run project formatter pre-commit), `rnd-cards` (flash-card priming system: cards prepended to a card-receiving agent's task spec under `# Reference examples for tasks like this one` immediately before `Task: T<id>`; five card-receiving roles: planner, builder, reality-auditor, verifier, cleanup; pre-reg may carry optional `Card tags: [tag1, tag2]`; orchestrator emits a `card_injection` audit event per spawn; `/rnd-framework:rnd-cards-propose` and `/rnd-framework:rnd-cards-impact` close the loop — human-in-the-loop, nothing auto-inserted).

**Shadowing:** Personal skills in user's `.claude/skills/` override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

**Plugin freshness (v2.1.81+):** ref-tracked plugins re-clone on every load, so the cached version is always current. The mismatch warning from `session-start.sh` should be rare in modern setups.

### Session Bootstrap

`SessionStart` fires on `startup|resume|clear|compact` → `hooks/session-start.sh` injects the `using-rnd-framework` skill as a system reminder and emits a version warning if below v2.1.139.

`SessionEnd` fires on close/switch (including `/resume`) → `hooks/session-end.sh` calls `rnd-dir.sh --finish` to clear `.current-session`.

**Remote pipelines:** `--channels` (v2.1.81+) forwards permission prompts to the Claude mobile app — useful for headless pipeline runs.

### Runtime Artifacts

Artifacts live in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated slug; each pipeline run gets a unique session ID.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR`. Flags: `-c` (create session under current branch), `--finish` (clear session), `--base` (branch-scoped project base), `--roadmap` / `--facts` (branch-scoped, lazy-inherit from default branch on first access), `--calibration` (slug-root, un-partitioned). Branch is resolved at each invocation via `git symbolic-ref --short HEAD`; detached HEAD → `detached-<sha7>`; non-git → `no-git`; slashes preserved as nested dirs; `..` rejected.

```
~/.claude/.rnd/<basename>-<hash>/          # Project slug; un-partitioned at the top
├── .active-base-dir                       # Cache: active branch-scoped base dir (fast-path in lib.sh::active_session_dir)
├── calibration.jsonl                      # Verdict-accuracy tracking, project-wide. Records may include: amendmentData {userDecision, arbitersRecommendation}; multiJudge {judgeA, judgeB, agreed, resolution, tiebreaker}; task_type (refactor|new-feature|bugfix|docs|config|infra); gateFired {gate, outcome, task_id}
└── branches/<branch>/                     # Branch-scoped partition (slashes → nested dirs)
    ├── .current-session                   # Active session ID
    ├── .session-git-root                  # Git root that started the session (written by session-start, read by cwd-changed)
    ├── roadmap.md                         # Multi-session roadmap (lazy-inherited from default branch)
    ├── project-facts.md                   # Persistent project scan (lazy-inherited from default branch)
    └── sessions/<YYYYMMDD-HHMMSS-XXXX>/   # $RND_DIR (one per pipeline run)
        ├── plan.md                        # Task tree, env, testing strategy, pre-registrations, schedule
        ├── diagnosis/T*-diagnosis.md      # Debugger root cause (debug pipeline only)
        ├── builds/T*-manifest.md          # Terse build records (structured bullets, no narrative)
        ├── builds/T*-self-assessment.md   # Builder uncertainties (blocked from Verifier)
        ├── builds/T*-found-issues.jsonl   # Per-task issue ledger ({issue, location, decision:"fixed"|"escalated", reason}) — enforced by builder-dismissal-gate
        ├── verifications/wave-*-verdict-map.json   # Per-wave verdicts keyed by task_id
        ├── verifications/T*-verification.md        # Full prose verdict report (for every verdict)
        ├── verifications/T*-experiments/  # Verifier-written independent tests
        ├── verifications/T*-evidence/     # Per-VAL-assertion raw output
        ├── evidence/T<id>/                # Builder-side evidence packs (opt-in: RND_EVIDENCE_PACK=1) — manifest.json + tool stdout/stderr/structured.json
        ├── audit.jsonl                    # Shared audit log: Write/Edit events from post-dispatch; tool_run_fresh from run-tool.sh; tool_pack_served from Verifier; lifecycle events; gateFired records
        ├── proofs/T*-proof-report.md      # Proof Gate results (Lean 4)
        ├── proofs/T*-theorems/            # Lean theorem files
        ├── integration/wave-*-report.md   # Integration results, SHIP/NO-SHIP
        ├── cleanup/T*-cleanup-report.md   # Cleanup reports (barrier-protected from Verifier)
        ├── polish/wave-*-polish-report.md # Polisher wave-level seam-fix reports
        ├── briefs/                        # Barrier-protected Builder-reasoning artifacts (blocked from Verifier by hooks)
        │   ├── decisions.md               # Cross-phase judgment-call log (rejected alternatives)
        │   ├── plan-briefs.md             # Planner user-facing narrative
        │   ├── T<id>-briefs.md            # Per-task user-facing narrative (Builder/Debugger)
        │   ├── wave-<N>-briefs.md         # Per-wave integration narrative
        │   └── T<id>-amendments.md        # Amendment-arbiter proposals (barrier-protected; orchestrator-owned write)
        └── iteration-log.md               # Build-verify cycle tracking
```

Since `$RND_DIR` is outside the project, no `.gitignore` entry is needed.

**Worktree support:** all worktrees of the same repo share `.rnd/<slug>/` because the slug is derived from `git rev-parse --git-common-dir` (canonicalized via the POSIX `cd + pwd` idiom). Worktrees on different branches partition into distinct `branches/<branch>/` buckets — each branch's facts/roadmap/sessions stay isolated. Same-branch worktrees share the bucket.

## Commands

Slash commands use the plugin namespace: `/rnd-framework:rnd-start`, `rnd-plan`, `rnd-build`, `rnd-verify`, `rnd-integrate`, `rnd-status`, `rnd-resume`, `rnd-history`, `rnd-validate`, `rnd-doctor`, `rnd-bump`, `rnd-review`, `rnd-audit`, `rnd-brainstorm`, `rnd-narrative`, `rnd-calibrate`, `rnd-debug`, `rnd-roadmap`, `rnd-scan`, `rnd-cards-propose`, `rnd-cards-impact`.

## Key Conventions

- **Skills use YAML frontmatter** — `name`, `description`, `effort` between `---` delimiters.
- **Commands are Markdown files** in `commands/` — filename becomes the command name.
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`.
- **Tests** — `tests/` contains bash tests for hooks and lib scripts; run with `tests/run-tests.sh` from `plugins/rnd-framework/`.
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools` skill), then bash scripts, then Python as last resort.
- **File creation** — always use `Write`/`Edit`, never bash heredocs (`cat > file << 'EOF'`).
- **Report surfacing** — the three output styles each carry a "Report Surfacing Protocol" requiring the orchestrator to print agent/skill report artifacts (plans, design specs, manifests, verdict maps, reality reports, diagnoses, integration reports, proofs, amendments, iteration log, audits, reviews, narratives, brainstorms) verbatim before any next-step prompt — same turn, including autonomous/loop mode. Excluded: self-assessments, found-issues ledgers, cleanup reports, project-facts, calibration, audit log.

## Working on This Codebase

Skills and commands are Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
