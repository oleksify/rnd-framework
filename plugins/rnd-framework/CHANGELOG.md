# Changelog

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