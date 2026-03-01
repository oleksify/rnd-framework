# Changelog

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
