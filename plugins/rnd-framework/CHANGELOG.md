# Changelog

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
