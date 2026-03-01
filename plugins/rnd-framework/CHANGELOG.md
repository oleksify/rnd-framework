# Changelog

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
