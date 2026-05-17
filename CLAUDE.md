# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing **rnd-framework** — a scientific-method orchestration system for structured coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition. Uses a multi-agent execution model: 11 specialized agents with structural isolation enforce the information barrier at the context-window level.

The plugin lives under `plugins/rnd-framework/`. The root `.claude-plugin/marketplace.json` is a local plugin registry. Plugins can also be declared inline in `settings.json` using `source: 'settings'` (v2.1.80+).

## Repository Layout

```
lib/
└── plugin-dir-base.sh              # Canonical copy of shared artifact directory logic (each plugin has its own copy for cache compatibility)

plugins/rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
├── agents/                      # 11 specialized agents for multi-agent execution mode
├── commands/                    # Slash commands (/rnd-framework:rnd-start, etc.)
├── skills/                      # Skills, each in its own dir with SKILL.md
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── hooks/
│   ├── hooks.json               # Hook routing: SessionStart/End, Setup, InstructionsLoaded, PreToolUse, PostToolUse, PreCompact/PostCompact, StopFailure, CwdChanged, FileChanged, TaskCreated, SubagentStart/Stop, PermissionDenied, WorktreeCreate/Remove
│   ├── lib.sh                   # Shared bash utilities (input parsing, path checks, decision output incl. defer)
│   ├── read-gate.sh             # Read hook: information barrier + .rnd/, plugin cache, and learnings auto-allow
│   ├── bash-gate.sh             # Bash hook: blocks sed/awk/echo>/inline interpreters/for-while-until loops//tmp redirects (including after env-var prefixes), auto-allows .rnd/ paths only; also handles commit protection (git add .rnd/ block, git push advisory)
│   ├── session-start.sh         # SessionStart hook: injects skill context + Claude Code version check
│   ├── session-end.sh           # SessionEnd hook: clears active RND session on close/switch
│   ├── post-dispatch.sh         # PostToolUse hook: audit logging for Write/Edit operations + advises when output exceeds 50 lines
│   ├── stop-failure.sh          # StopFailure hook: logs API errors to stop-failures.jsonl, emits advisory
│   ├── setup.sh                 # Setup hook: validates plugin structure and dependencies
│   ├── instructions-loaded.sh   # InstructionsLoaded hook: reminds to extract project standards
│   ├── pre-compact.sh           # PreCompact hook: saves pipeline state before context compaction
│   ├── post-compact.sh          # PostCompact hook: restores pipeline state after compaction
│   ├── cwd-changed.sh           # CwdChanged hook (v2.1.83+): warns on cross-repo directory change
│   ├── file-changed.sh          # FileChanged hook (v2.1.83+): advises on external .rnd/ artifact edits
│   ├── task-created.sh          # TaskCreated hook (v2.1.84+): logs task creation to audit.jsonl
│   ├── permission-denied.sh     # PermissionDenied hook (v2.1.89+): logs auto-mode denials to audit.jsonl, returns {retry: true}
│   ├── write-gate.sh             # Write/Edit hook: auto-allows .rnd/ path operations
│   ├── glob-grep-gate.sh        # Glob/Grep hook: information barrier + .rnd/ auto-allow
│   ├── format-on-save.sh        # PostToolUse hook (v2.1.90+): auto-formats code files after Write/Edit using detected project formatter
│   ├── session-title.sh         # UserPromptSubmit hook (v2.1.94+): sets session title to pipeline phase + project name
│   ├── subagent-lifecycle.sh    # SubagentStart/SubagentStop hook: logs agent lifecycle to audit.jsonl
│   ├── builder-dismissal-gate.sh # SubagentStop hook scoped to rnd-builder: blocks dismissal phrases, acknowledged-but-unfixed issues, and missing/empty found-issues ledger
│   ├── coverage-gaps-gate.sh    # SubagentStop hook scoped to rnd-verifier: blocks completion when the most recent T<id>-verification.md lacks a `## Coverage Gaps` section, or its content matches the trivial-content denylist (nothing|none|n/a|all checks ran|no gaps); emits gateFired audit event on every block
│   ├── stop-condition-revisions.sh # PreToolUse Write|Edit hook: counts prior Write/Edit events to the same path for the active task via lib/audit-scan.sh; blocks with STOP CONDITION when count >= RND_STOP_FILE_REVISIONS (default 5); emits gateFired audit event on halt
│   ├── evidence-pack-gate.sh    # PreToolUse Read hook: blocks Verifier reads of evidence-pack manifests that contain disallowed free-text fields (notes, summary, confidence, reasoning, explanation); information barrier check runs first, schema gate second
│   ├── worktree-create.sh      # WorktreeCreate hook (v2.1.83+): emits worktree_created audit event when an agent worktree is created
│   ├── worktree-remove.sh      # WorktreeRemove hook (v2.1.83+): emits worktree_removed audit event when an agent worktree is removed
│   └── statusline.sh            # Statusline script: rate limit usage + pipeline phase + worktree indicator (v2.1.80)
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   ├── plugin-dir-base.sh       # Local copy of shared artifact dir logic (cache-compatible)
│   ├── bump.sh                  # Patch version increment + CHANGELOG entry + git stage + `claude plugin tag` auto-tag (v2.1.118+)
│   ├── validate.sh              # Plugin structure validation (frontmatter, hooks, cross-references)
│   ├── validate-xrefs.sh        # Cross-reference and content parity validation (sourced by validate.sh)
│   ├── tools.json               # Plugin-default registry of heavy tools (pytest/jest/vitest/tsc/eslint/dialyzer/mypy/bun/cargo/mix/ruff/biome) with structured-output flags AND relevant_globs (per-tool input scoping — pytest hashes only *.py + Python config files, etc.); project may override at $RND_DIR/tools.json
│   ├── run-tool.sh              # Evidence-pack writer: opt-in via RND_EVIDENCE_PACK=1; wraps a heavy-tool invocation, captures stdout/stderr/structured output, hashes inputs[] filtered by tool's relevant_globs, writes manifest.json + tool_run_fresh audit event; passthrough exec when flag unset
│   ├── manifest-schema.json     # JSON Schema (draft-07) for the evidence-pack manifest; load-bearing — its `x-disallowed-fields` extension is sourced at runtime by evidence-pack-gate.sh (single source of truth for the disallowed-fields list)
│   ├── audit-event.sh           # Shared audit-event emitter: writes a single {event,task_id,tool,timestamp} line to $RND_DIR/audit.jsonl; called by run-tool.sh for tool_run_fresh and by the Verifier (per rnd-verification skill) for tool_pack_served
│   ├── audit-scan.sh            # audit.jsonl scanner: subcommand `revisions <task_id> <file_path>` returns count of Write/Edit events; subcommand `verdict_history <task_id>` returns the verdict sequence parsed from verifications/, printing FLIP_DETECTED on PASS/FAIL/PASS or FAIL/PASS/FAIL; consumed by stop-condition-revisions.sh and by orchestration's Stop Conditions section
│   ├── rnd-undo.sh              # Surgical task-scoped revert: reads `## Files written` section from $RND_DIR/builds/T<id>-manifest.md and reverts only those files (git checkout HEAD or rm); blocking destructive git ops in bash-gate.sh redirect agents here
│   └── calibration.sh           # Calibration auto-escalation helpers: window/false_pass_rate/should_promote/promote_tier/task_type_window subcommands; orchestrator invokes should_promote before each adaptive-agent spawn to react to model-quality drift; task_type_window prints the last N records filtered by the task_type enum (refactor|new-feature|bugfix|docs|config|infra) for per-task-type reliability reporting; RND_DISABLE_AUTO_ESCALATION=1 disables
├── proofs/                      # Lean 4 formal verification of pipeline invariants
└── README.md
```

## Architecture

### Execution Model

Eleven specialized agents handle each pipeline phase in isolated context windows. The orchestrator dispatches work to agents, enforcing structural information barriers — the Verifier literally cannot see the Builder's reasoning because they run in separate context windows.

| Phase | Agent | Purpose |
|---|---|---|
| Planning | `rnd-planner` (opus/high, adaptive) | Decomposes tasks into pre-registered sub-tasks with testable criteria; capped at max 4 tasks/wave with min 1-hour scope and forced coalescing; emits `Heuristic ceiling: <integer>` as a meta-field in plan.md (consumed by the orchestration plan-size stop condition: halt when actual `task_count > RND_STOP_PLAN_RATIO * ceiling`, default ratio 1.5); pre-registrations include a required `## Assumptions` section with `Assumption: ... Refuted by: ...` form (placeholder `- None` when no assumptions exist) — the Verifier downgrades a verdict by one tier and emits a `gateFired: {gate: "assumption_unchecked"}` calibration record when an Assumption's Refuted-by action was declared but not executed |
| Building | `rnd-builder` (sonnet/high, adaptive, worktree) | Implements tasks using TDD; produces build manifest + self-assessment |
| Reality Audit | `rnd-reality-auditor` (sonnet/low) | Per-task audit of declared external references (URLs, APIs, schemas, env vars, data); only runs when the task declares `External dependencies`; runs an "Existence Pre-Pass" Step 0 (mechanical probes — file-execution only, no `python -c`/`node -e`/`bun -e`) that verifies every imported module / third-party method call / RFC or error-code citation / env-var name actually exists in the form claimed, before adversarial experiments; MISSING short-circuits to `INVALID_FOUND` and emits a `FALSE_PASS_PROXY` calibration record if a prior Builder PASS exists for the task |
| Proof Gate | `rnd-proof-gate` (sonnet/low) | Formal Lean 4 proofs of pre-registration criteria (advisory); only runs when the task has `Proof: lean` and Lean is on PATH; amendments to proven criteria force a re-prove before re-verification |
| Verification | `rnd-verifier` (sonnet/high, adaptive, worktree) | Wave-batched: one spawn per wave reviews all task pre-regs and emits a per-task verdict map; writes `T<id>-verification.md` full prose report for every verdict (PASS, FAIL, NEEDS_ITERATION, PASS_QUALITY_NEEDS_ITERATION, AMEND_REQUIRED) with a required `## Coverage Gaps` section (`Checked:` + `Couldn't check:` sub-bullets — enforced structurally by `coverage-gaps-gate.sh` SubagentStop hook, which also rejects trivial content); AMEND_REQUIRED (emit only with cited concrete spec defect; routes to amendment arbiter; clean-slate re-verification afterward) pauses the task without blocking the wave; information barrier enforced; HIGH criticality routes through wave-batched multi-judge with verdict-based escalation gate (single first-pass verifier; only FAIL/NEEDS_ITERATION/PASS_QUALITY_NEEDS_ITERATION/AMEND_REQUIRED escalates to full dual-judge; set `RND_MULTI_JUDGE_ALWAYS=1` to bypass gate and restore exact pre-gate always-dual-judge behavior) |
| Amendment | `rnd-amendment-arbiter` (opus/xhigh, non-adaptive) | Evaluates AMEND_REQUIRED verdicts; proposes spec corrections (AMEND), recommends rebuild (REBUILD), or routes to Planner re-plan (ESCALATE_REPLAN); inputs strictly limited to original pre-reg + Verifier verdict |
| Cleanup | `rnd-cleanup` (sonnet/medium, worktree) | Per-task dead-code sweep after Verifier PASS; detects dead functions, orphan files, duplicate implementations, stale comments; applies fixes and rolls back if cleanup breaks re-verification |
| Polish | `rnd-polisher` (opus/high, non-adaptive, per-wave, worktree) | Wave-level cross-task seam fixer: detects cross-task duplication, naming and API drift, helpers that should be lifted to shared locations, and structural inconsistencies; runs after all per-task cleanup; rolls back if re-verification breaks; reports to `$RND_DIR/polish/wave-<N>-polish-report.md` |
| Integration | `rnd-integrator` (haiku/low) | Merges verified outputs, runs integration/system tests |
| Debugging | `rnd-debugger` (sonnet/high, adaptive, worktree) | Root cause analysis for failing tasks |
| Data Science | `rnd-data-scientist` (sonnet/medium) | Standalone specialist for numerical/analytical work |

**Dispatch Policy (criticality-driven, per-agent):** the orchestrator overrides the spawned agent's model based on the per-task `Criticality` field. The mapping is per-agent, not a single global table:

| Agent | LOW | MEDIUM | HIGH |
|---|---|---|---|
| `rnd-planner` | opus/high | opus/high | opus/xhigh |
| `rnd-verifier` | sonnet/high | opus/high | opus/xhigh |
| `rnd-builder` | sonnet/high | sonnet/high | opus/high |
| `rnd-debugger` | sonnet/high | sonnet/high | opus/high |
| `rnd-amendment-arbiter` (non-adaptive) | opus/xhigh | opus/xhigh | opus/xhigh |
| `rnd-polisher` (non-adaptive, per-wave) | opus/high | opus/high | opus/xhigh |

If `Criticality` is absent (or no pre-reg exists), the orchestrator does NOT override and the agent's frontmatter `model:` is used as the fallback. Effort is NOT per-spawn overridable; it stays at the agent's frontmatter value. Non-adaptive agents (`rnd-amendment-arbiter`, `rnd-polisher`) always run at their listed model regardless of criticality. Full policy lives in `rnd-framework:rnd-orchestration` skill under "Dispatch Policy".

### Information Barrier and Permission Hooks

The `hooks.json` routes each PreToolUse event to an external script. Policies enforced:
- **Information barrier** (`read-gate.sh`, `glob-grep-gate.sh`, `bash-gate.sh`): Blocks any tool call where the file path or command string contains `self-assessment`, the path segment `/briefs/`, or the path segment `/cleanup/` when the agent is a verifier, the proof-gate, or has no agent_type, preventing the verification and proof phases from anchoring on build-phase or cleanup-phase reasoning. The proof-gate is included so the runtime matches the Lean theorem `proofGate_cannot_access_self_assessment` in `proofs/InformationBarrier.lean`. All three barrier-protected patterns share the same semantics. The `/briefs/` and `/cleanup/` segments (with slashes) are matched so the bare words "brief" or "cleanup" in a grep pattern are not flagged. Enforced across all file-reading tools: `Read` (path check), `Grep`/`Glob` (path and pattern check), `Bash` (command string check). The `/briefs/` protection covers the Planner/Builder/Debugger/Integrator user-facing brief artifacts under `$RND_DIR/briefs/` and the cross-phase `decisions.md` log located there. The `/cleanup/` protection covers the cleanup agent's per-task reports under `$RND_DIR/cleanup/`.
- **Auto-allow plugin artifact paths and cache operations** (`read-gate.sh`, `write-gate.sh`, `bash-gate.sh`, `glob-grep-gate.sh`, `settings.json`): `Read` operations on `.rnd/` artifact paths are auto-allowed via hook. `Write` and `Edit` operations on `.rnd/` paths are auto-allowed via hook (`write-gate.sh`) with `settings.json` `allowWrite` as belt-and-suspenders. `Glob` and `Grep` operations targeting these paths are auto-allowed via hook. For `Bash`, `.rnd/` auto-allow fires at the command level after tool-discipline segment checks have all passed — so sed and inline interpreters are still blocked even when a `.rnd/` path appears in the command. `read-gate.sh` additionally auto-allows reads from the plugin cache (`plugins/cache/`) for skill and agent files, and from the learnings directory (`$CLAUDE_CONFIG_DIR/learnings/`) for cross-session knowledge
- **Worktree topology** (write-side agents only): The five write-side adaptive agents — `rnd-builder`, `rnd-verifier`, `rnd-cleanup`, `rnd-polisher`, `rnd-debugger` — declare `isolation: "worktree"` in their frontmatter and spawn into per-task git worktrees at `.rnd-worktrees/<session_id>/T<id>/` checked out from ephemeral branches `rnd/<session_id>/T<id>`. Read-side agents (`rnd-planner`, `rnd-integrator`) run in the main checkout and are NOT worktree-isolated. The `$RND_DIR` artifact tree lives under `~/.claude/.rnd/` — entirely OUTSIDE any worktree — so build manifests, evidence packs, verification reports, briefs, and `audit.jsonl` remain readable across all agents regardless of worktree boundary; the information barrier is enforced by hooks, not by filesystem topology. Only the project source tree is scoped per agent, which bounds destructive operations to the per-task worktree. The `rnd-integrator` is the sole merge path back to main: it fetches each verified task's worktree branch and merges with `git merge --no-ff` in pre-registration dependency order, then prunes branches and worktrees.
- **Tool discipline** (`bash-gate.sh`): Blocks `sed`, `awk`, `echo/printf` with file redirects, inline interpreter execution (`python -c`, `node -e`, `bun -e`, bare interpreter as pipe target), shell loops (`for`/`while`/`until`), and `/tmp/` redirects — enforces use of dedicated Claude Code tools and `$RND_DIR` for temp storage. Read-side commands (`cat`, `head`, `tail`, `grep`, `rg`, `find`) pass through without opinion. Splits compound commands (`&&`, `||`, `;`, `|`) and checks each segment, including `$()` and backtick substitutions. Strips environment-variable prefixes (`FOO=bar command`) before checking each segment, ensuring tool discipline applies regardless of env-var assignments. File execution (`python file.py`, `bun test`, `python -m pytest`) is allowed. Also handles commit protection: blocks `git add` of `.rnd/` artifact directories and emits an advisory warning on `git push` to main/master/production branches. **Note on Edit-without-Read (v2.1.89+):** Claude Code v2.1.89 allows Edit on files viewed via `sed -n` or `cat` without a separate Read call. Since bash-gate blocks `sed`, this upstream feature does not affect rnd-framework users — the model must still use Read → Edit.
- **Audit logging** (`post-dispatch.sh`): PostToolUse hook logs all Write and Edit operations to `$RND_DIR/audit.jsonl` and advises when command output exceeds 50 lines
- **Bash output cache** (`post-dispatch.sh` writer + `bash-gate.sh` advisory): PostToolUse Bash writes stdout (plus stderr if present) to `$session_dir/.bash-cache/<sha>.txt` and a sibling `<sha>.meta.json` keyed by a 16-char sha-256 of the whitespace-normalized command. PreToolUse Bash detects identical re-runs within `RND_BASH_CACHE_TTL_SECONDS` (default 600) and emits an advisory pointing the agent to the cached file when output is ≥10 lines — solving the "ran `mix test | tail -30`, then re-ran `mix test | grep failure`" pattern. Non-blocking: agent may still re-run when fresh output is needed (e.g. after file changes). Cache lives inside the session dir so it auto-clears with each pipeline run; no GC required. Hash semantics are shared between writer and advisory via `cmd_hash` in `lib.sh` (single source of truth).
- **Stop failure logging** (`stop-failure.sh`): StopFailure hook logs API errors (rate limits, auth failures) to `$RND_DIR/stop-failures.jsonl` and emits advisory context
- **Directory change detection** (`cwd-changed.sh`): CwdChanged hook (v2.1.83+) warns when the working directory moves to a different git repository while an RND session is active
- **Artifact change detection** (`file-changed.sh`): FileChanged hook (v2.1.83+) emits advisory context when `.rnd/` artifact files (plan.md, iteration-log.md) are modified externally
- **Task creation logging** (`task-created.sh`): TaskCreated hook (v2.1.84+) logs task creation events to `$RND_DIR/audit.jsonl`
- **Agent lifecycle logging** (`subagent-lifecycle.sh`): SubagentStart and SubagentStop hooks log agent spawn/completion events to `$RND_DIR/audit.jsonl` for pipeline observability. No-opinion — does not affect permission flow.
- **Builder dismissal gate** (`builder-dismissal-gate.sh`): SubagentStop hook that fires only for the `rnd-builder` agent. Reads the most recent `T<id>-manifest.md` under the active session and runs three structural checks: (a) phrase scan blocks on `pre-existing`, `out of scope`, `not my task`, `unrelated to this task`, `won't fix here`, `outside scope`; (b) acknowledged-but-unfixed scan requires a co-located `T<id>-found-issues.jsonl` ledger when the manifest mentions a problem; (c) ledger-required check blocks DONE manifests that report failures without a ledger entry. The only legal dismissal path is appending a JSON line `{"issue", "location", "decision":"escalated", "reason"}` to the ledger; the Verifier reads the ledger and re-fails the task on any unacknowledged escalation. Replaces the textual "never use 'pre-existing' as a reason" rules in agent prompts with structural enforcement.
- **Coverage Gaps gate** (`coverage-gaps-gate.sh`): SubagentStop hook that fires only for the `rnd-verifier` agent. Reads the most recent `T<id>-verification.md` and blocks completion with exit 2 when (a) the `## Coverage Gaps` heading is absent OR (b) the section's content matches the trivial-content denylist regex (`nothing|none|n/a|all checks ran|no gaps`, case-insensitive, whole-bullet anchored to avoid substring false-positives like "Couldn't check: none of the upstream APIs were reachable"). Emits a `gateFired` audit event with gate name `coverage_gaps_gate` on every block. Mirrors the builder-dismissal-gate's fast-path + lib.sh-sourcing pattern.
- **File-revision stop condition** (`stop-condition-revisions.sh`): PreToolUse Write|Edit hook that counts prior Write/Edit events to the same path for the active task by querying `lib/audit-scan.sh revisions`. Blocks with exit 2 and a "STOP CONDITION" message when the count meets the threshold (default 5; overridable via `RND_STOP_FILE_REVISIONS`). Tolerates `task_id` absence in older `audit.jsonl` records by falling back to the active-session marker. Emits a `gateFired` audit event with gate name `stop_condition_revisions` on every halt. The matching post-hoc verdict-flip and plan-size stop conditions are enforced at the orchestration-prompt level (see `rnd-framework:rnd-orchestration` § Stop Conditions), not by hook; both invoke `AskUserQuestion` and emit gate names `stop_condition_verdict_flip` and `stop_condition_plan_size`.
- **Permission denial handling** (`permission-denied.sh`): PermissionDenied hook (v2.1.89+) fires after auto-mode classifier denials. Logs the denied tool name and timestamp to `$RND_DIR/audit.jsonl` and returns `{retry: true}` so the model can retry the tool call with adjusted parameters. This prevents auto-mode denials from silently breaking pipeline execution.
- **Format-on-save** (`format-on-save.sh`): PostToolUse hook (v2.1.90+) for Write and Edit events. Auto-detects the project's code formatter and runs it on changed code files. Detection is cached at session level. Skips non-code files and `.rnd/` artifacts. Non-blocking — formatting errors do not affect the pipeline.
- **Evidence pack gate** (`evidence-pack-gate.sh`): PreToolUse Read hook that runs the existing information-barrier check first (still blocks self-assessment / `/briefs/` / `/cleanup/` for the verifier and proof-gate), then — only when the agent is `rnd-verifier` and the path matches `$RND_DIR/evidence/T*/manifest.json` — validates the manifest by `jq has()` checks against the disallowed-fields list sourced from `lib/manifest-schema.json`'s `x-disallowed-fields` extension (default: `notes`, `summary`, `confidence`, `reasoning`, `explanation`). The schema file is the single source of truth; the hook falls back to a hard-coded mirror only if the schema is unreadable. Blocks with `EVIDENCE PACK BARRIER` if any disallowed field is present; emits `allow` for clean manifests; no opinion for non-manifest paths or non-verifier agents. Registers as a second `Read` PreToolUse entry in `hooks.json`, ordered before `read-gate.sh`.
- **Session title** (`session-title.sh`): UserPromptSubmit hook (v2.1.94+) that dynamically sets the session title to reflect the current pipeline phase and project name. When no active RND session exists, the title is `RND: <project>`. During pipeline execution, it becomes `RND: <phase> | <project>` (e.g., `RND: Building | my-project`). This makes sessions identifiable in the `/resume` picker. Always exits 0 — does not block prompt submission.

#### Claude Code Version Notes

**Min recommended:** v2.1.139 (`hooks.json` exec form for `args: string[]`; bumped from v2.1.117 in 3.20.5). `session-start.sh` warns when below threshold via `claude --version`; degrades gracefully if `claude` not in PATH.

**Hook Allow/Deny Precedence (v2.1.77+):** `deny rules > hook allow > default prompt`. A deny rule covering `.rnd/` silently overrides auto-allows. **Workaround:** add `allowRead`/`allowWrite` sandbox settings (these take precedence over deny rules):
```json
{ "allowRead": ["~/.claude/.rnd/**"], "allowWrite": ["~/.claude/.rnd/**"] }
```

**Symlink Resolution (v2.1.89+):** `allowWrite`/`allowRead` check resolved targets, so `["~/.claude*/.rnd/**"]` matches symlinked `.claude` or `.rnd`.

**Hook Output Size (v2.1.89+):** Output exceeding 50K chars saves to disk with preview. `session-start.sh` is ~5-10K, well under threshold.

**Auto-Mode Boundary Respect (v2.1.90+):** Auto mode honors explicit user boundaries even when the classifier would allow. Pipeline agents spawn with `mode: "acceptEdits"` (empirically `mode: "auto"` denied project-file Edit/Write on 2.1.112 team-spawned subagents); Bash still routes through the classifier.

**Format-on-Save (v2.1.90+):** Required minimum — earlier versions failed Write/Edit with "File content has changed" when a PostToolUse hook rewrote the file.

**Default Effort (v2.1.94+):** Default raised from medium to high for API-key/Bedrock/Vertex/Foundry/Team/Enterprise users; affects agents spawned without explicit `effort`.

**keep-coding-instructions (v2.1.94+):** All three rnd-framework output styles set this `true` to preserve coding instructions across compaction.

**Statusline (v2.1.97+):** `refreshInterval: 5` in `settings.json`; `workspace.git_worktree` extracted by `statusline.sh` as `[wt: <name>]`.

**Subagent cwd Isolation (v2.1.97+):** Fixed agents leaking cwd to parent — improves multi-agent mode.

**429 Backoff (v2.1.97+):** Exponential backoff applied as minimum, preventing retry budget burn on small `Retry-After`.

**sandbox.network.deniedDomains (v2.1.113+):** Plugin ships conservative default denylist (`pastebin.com`, `hastebin.com`, `0x0.st`, `transfer.sh`) as defense-in-depth against exfiltration via `WebFetch`/`Bash`.

**Subagent Stall Timeout (v2.1.113+):** 10-min timeout surfaces concrete error on hangs; does not on its own resolve the `rnd-integrator` hang documented in project memory.

**Bash find -exec/-delete (v2.1.113+):** Stopped auto-approving destructive `find`. `bash-gate.sh` already blocks `find` unconditionally so no user impact.

**Agent-Type Hooks (v2.1.118+):** Fixed agent-scoped hooks failing on non-Stop events; unblocks per-agent PreToolUse hooks.

**SendMessage cwd Restore (v2.1.118+):** Fixed resumed agents not restoring spawn-time `cwd`; pipeline uses SendMessage to wake sleeping agents.

#### file_path Handling

Tool schemas require absolute paths but hooks receive raw `tool_input`. Regex matchers in `lib.sh` (`is_plugin_artifact_path`, `is_plugin_cache_path`, `is_learnings_path`) reject paths not starting with `/` — relative paths fall through to the default permission prompt rather than auto-allowing.

#### Plugin Settings Defaults

`settings.json` ships pipeline-optimized defaults: `showThinkingSummaries: true`, `showTurnDuration: true`, `spinnerTipsEnabled: false`, `statusLines.refreshInterval: 5`, and `autoMode.allow` with the v2.1.118 `$defaults` keyword plus safe pipeline Bash invocations (`bun test:*`, `python -m pytest:*`, read-only `git`, `jq:*`, `ls:*`). User settings take precedence.

### --bare Mode (v2.1.81+)

When Claude Code is launched with `--bare`, all hooks are skipped — SessionStart, read-gate.sh, bash-gate.sh, post-dispatch.sh, and all others. Practical consequences:

- The information barrier is not enforced: verification phase can read build-phase self-assessments
- Tool discipline is not enforced: sed/cat/grep/find/inline interpreters bypass is possible
- Session bootstrap does not run: skills are not injected into context

Bottom line: rnd-framework effectively does not work in `--bare` mode. This is expected — `--bare` is designed for scripted `-p` invocations, not interactive pipeline orchestration.

### Skill System

Skills are directories under `skills/` containing a `SKILL.md` with YAML frontmatter (`name`, `description`, `effort`). Claude Code's native plugin system discovers skills by directory convention. The `effort` field (added in v2.1.80) overrides the model's reasoning effort when the skill is invoked: `low` for reference/guidance skills, `medium` for procedural workflows. Commands also support `effort` frontmatter: `low` for read-only operations, `medium` for moderate reasoning, `high` for deep pipeline orchestration.

The `rnd-roadmapping` skill defines the roadmap.md format, milestone statuses, and how to create and update roadmaps across sessions.

The `rnd-learning` skill enables auto-capture of pipeline-discovered gotchas to the user's Learning Library during iteration cycles.

The `rnd-formatting` skill detects the project's code formatter and runs it on pipeline-changed files before doc-polish and committing.

**Shadowing rule:** Personal skills (in user's `.claude/skills/`) override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

**Plugin freshness (v2.1.81+):** Ref-tracked plugins re-clone on every load, so the cached plugin version is always current. Version mismatch warnings (from `hooks/session-start.sh`) should be rare in v2.1.81+ setups; if they appear, it likely indicates a bug rather than a stale install.

### Session Bootstrap

The `SessionStart` hook fires on `startup|resume|clear|compact` and runs `hooks/session-start.sh`, which reads and injects the `using-rnd-framework` skill content into session context as a system reminder. It also checks the installed Claude Code version against the minimum recommended (v2.1.139) and emits a warning if below threshold.

The `SessionEnd` hook fires when a session closes or switches (including via `/resume`) and runs `hooks/session-end.sh`, which calls `rnd-dir.sh --finish` to clear the active session marker. This prevents stale `.current-session` files from persisting across sessions.

**Remote pipelines with `--channels` (v2.1.81+):** The `--channels` flag enables permission-relay mode, forwarding tool approval prompts to the Claude mobile app. This is useful when running rnd-framework pipelines on remote or headless machines where interactive terminal input is unavailable.

### Runtime Artifacts

The framework stores artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated artifact space based on a hash of its path. Each pipeline run gets a unique session ID, preserving history across runs.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR` path. Flags: `-c` (create session under current branch), `--finish` (clear session), `--base` (branch-scoped project base dir), `--roadmap` (path to roadmap.md; branch-scoped; lazy-inherits from default branch on first access), `--facts` (path to project-facts.md; branch-scoped; lazy-inherits from default branch on first access), `--calibration` (path to calibration.jsonl at the un-partitioned slug root). Branch is resolved at each invocation via `git symbolic-ref --short HEAD`; detached HEAD becomes `detached-<sha7>`; non-git directories become `no-git`; slashes preserve as nested dirs; `..` traversal is rejected.

```
~/.claude/.rnd/<basename>-<hash>/          # Project slug; un-partitioned at the top
├── .active-base-dir                       # Cache: path to the currently active branch-scoped base dir (read by lib.sh::active_session_dir fast-path)
├── calibration.jsonl                      # Verdict accuracy tracking (project-wide, un-partitioned; legacy — new installs use $CLAUDE_PLUGIN_DATA); AMEND_REQUIRED verdicts include optional amendmentData field: { userDecision: "approved"|"rejected", arbitersRecommendation: "AMEND"|"REBUILD"|"ESCALATE_REPLAN" }; additional optional nested objects: multiJudge ({judgeA, judgeB, agreed, resolution, tiebreaker} — written by the rnd-multi-judge skill Step 5 to record pre-resolution disagreement); task_type (enum: refactor|new-feature|bugfix|docs|config|infra — rule-based keyword inference from pre-reg Intent + title, default infra; surfaced via `lib/calibration.sh task_type_window <type>`); gateFired ({gate, outcome, task_id} — emitted by every new pipeline gate: existence_prepass, stop_condition_revisions, stop_condition_verdict_flip, stop_condition_plan_size, coverage_gaps_gate, assumption_unchecked)
└── branches/<branch>/                     # Branch-scoped partition (branch resolved from HEAD; detached-<sha7> / no-git fallbacks; nested dirs for slash-names like feature/foo)
    ├── .current-session                   # Active session ID
    ├── .session-git-root                  # Git root of the project that started the session (written by session-start.sh, read by cwd-changed.sh)
    ├── roadmap.md                         # Multi-session roadmap (optional, created by /roadmap); lazily copied from default branch on first access
    ├── project-facts.md                   # Persistent project environment scan (created by /rnd-scan); lazily copied from default branch on first access
    └── sessions/<YYYYMMDD-HHMMSS-XXXX>/   # $RND_DIR (one per pipeline run)
    ├── plan.md                            # Task tree, environment, testing strategy, worker guidelines, validation contract, pre-registrations (with preconditions), schedule
    ├── diagnosis/T*-diagnosis.md          # Debugger root cause analysis (debug pipeline only)
    ├── builds/T*-manifest.md              # Builder output records (terse: structured bullets, no narrative)
    ├── builds/T*-self-assessment.md       # Builder uncertainties (blocked from Verifier)
    ├── builds/T*-found-issues.jsonl       # Per-task ledger of issues encountered: {"issue","location","decision":"fixed"|"escalated","reason"}; enforced by builder-dismissal-gate.sh; read by Verifier

    ├── verifications/wave-*-verdict-map.json  # Per-wave verdict map keyed by task_id (PASS/PASS_QUALITY_NEEDS_ITERATION/NEEDS_ITERATION/FAIL + evidence + feedback)
    ├── verifications/T*-verification.md   # Verifier evidence-based verdicts (full prose report written for every verdict: PASS, FAIL, NEEDS_ITERATION, PASS_QUALITY_NEEDS_ITERATION, AMEND_REQUIRED — replaces the retired T*-pass-receipt.json lazy-prose path)
    ├── verifications/T*-experiments/      # Verifier-written independent experiment tests
    ├── verifications/T*-evidence/         # Per-VAL-assertion evidence files (raw command output)
    ├── evidence/T<id>/                    # Evidence-pack writer output (Builder-side, opt-in via RND_EVIDENCE_PACK=1): one dir per task containing manifest.json (schema-validated by evidence-pack-gate.sh before Verifier reads), <tool>-stdout.txt, <tool>-stderr.txt, optional <tool>-structured.json
    ├── audit.jsonl                        # Shared audit log; post-dispatch.sh emits {ts,tool,file} per Write/Edit; run-tool.sh emits {event:"tool_run_fresh",task_id,tool,timestamp} per evidence-pack run via lib/audit-event.sh; Verifier emits {event:"tool_pack_served",...} on hash-match by calling the same helper (per rnd-verification skill)
    ├── proofs/T*-proof-report.md          # Proof Gate results (Lean 4 formal verification)
    ├── proofs/T*-theorems/                # Lean theorem files
    ├── integration/wave-*-report.md       # Integration results, SHIP/NO-SHIP
    ├── cleanup/T*-cleanup-report.md        # Cleanup agent per-task reports (barrier-protected from Verifier)
    ├── polish/wave-*-polish-report.md      # Polisher wave-level seam-fix reports (Phase 4.5, one per wave)
    ├── briefs/                             # Barrier-protected Builder-reasoning artifacts (blocked from Verifier by read-gate/glob-grep-gate/bash-gate hooks)
    │   ├── decisions.md                    # Cross-phase structured judgment-call log (Planner/Builder/Debugger/Integrator append when rejecting real alternatives)
    │   ├── plan-briefs.md                  # Planner user-facing narrative briefs
    │   ├── T<id>-briefs.md                 # Per-task user-facing narrative briefs (Builder/Debugger)
    │   ├── wave-<N>-briefs.md              # Per-wave user-facing integration briefs
    │   └── T<id>-amendments.md             # Amendment arbiter proposals (barrier-protected from Verifier and Proof Gate; orchestrator-owned write)
    └── iteration-log.md                   # Build-verify cycle tracking
```

Since `$RND_DIR` is outside the project, no `.gitignore` entry is needed.

**Worktree support:** All worktrees of the same repository share the same `.rnd/<slug>/` base directory. Worktrees on different branches partition into distinct `branches/<branch>/` buckets — each branch's facts, roadmap, and sessions stay isolated. Worktrees on the same branch share the same branch bucket. The project slug is derived from `git rev-parse --git-common-dir` (canonicalized to an absolute path via the POSIX `cd + pwd` idiom), so linked worktrees and the main checkout produce identical slugs even though their `pwd` values differ.

## Commands

Slash commands use the full plugin namespace: `/rnd-framework:rnd-start`, `/rnd-framework:rnd-plan`, `/rnd-framework:rnd-build`, `/rnd-framework:rnd-verify`, `/rnd-framework:rnd-integrate`, `/rnd-framework:rnd-status`, `/rnd-framework:rnd-resume`, `/rnd-framework:rnd-history`, `/rnd-framework:rnd-validate`, `/rnd-framework:rnd-doctor`, `/rnd-framework:rnd-bump`, `/rnd-framework:rnd-review`, `/rnd-framework:rnd-audit`, `/rnd-framework:rnd-brainstorm`, `/rnd-framework:rnd-narrative`, `/rnd-framework:rnd-calibrate`, `/rnd-framework:rnd-debug`, `/rnd-framework:rnd-roadmap`, `/rnd-framework:rnd-scan`.

## Key Conventions

- **Skills use YAML frontmatter** — `name`, `description`, and `effort` fields between `---` delimiters
- **Commands are Markdown files** in `commands/` — filename becomes the command name
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`
- **Test suite** — `tests/` contains bash tests for hooks and lib scripts; run with `tests/run-tests.sh` from `plugins/rnd-framework/`
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools`), then bash scripts, then Python as last resort
- **File creation** — always use `Write`/`Edit` tools, never bash heredocs (`cat > file << 'EOF'`)
- **Report surfacing** — the three rnd-framework output styles each carry a "Report Surfacing Protocol" section that requires the orchestrator to print agent/skill report artifacts (plans, design specs, manifests, verifier verdict maps, reality reports, diagnoses, integration reports, proofs, amendments, iteration log, audits, reviews, narratives, brainstorms) verbatim before any next-step prompt — same turn, including autonomous/loop mode. Excluded: self-assessments, found-issues ledgers, cleanup reports, project-facts, calibration, audit log. The `using-rnd-framework` skill, `README.md`, and report-producing command files (`rnd-audit`, `rnd-review`, `rnd-brainstorm`, `rnd-debug`, `rnd-roadmap`) carry pointer reminders.

## Working on This Codebase

When modifying skills or commands, the content is Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new Claude Code session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
