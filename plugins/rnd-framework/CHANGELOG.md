# Changelog

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