# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing two plugins:

- **rnd-framework** — a scientific-method orchestration system for multi-agent coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.
- **** — a creative studio for designing in Framer. Follows a real design process (brief → moodboard → tokens → build → review) to produce design systems and page skeletons.

Plugins live under `plugins/`. The root `.claude-plugin/marketplace.json` is a local plugin registry that references them. Alternatively, plugins can be declared inline in `settings.json` using `source: 'settings'` (v2.1.80+).

## Repository Layout

```
plugins/rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
├── agents/                      # Specialized agents (planner, builder, verifier, integrator, data-scientist)
├── commands/                    # Slash commands (/rnd-framework:start, etc.)
├── skills/                      # Skills, each in its own dir with SKILL.md
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── hooks/
│   ├── hooks.json               # SessionStart + SessionEnd bootstrap + PreToolUse + PostToolUse hook routing
│   ├── lib.ts                   # Shared TypeScript utilities (input parsing, path checks, decision output)
│   ├── read-gate.ts             # Read hook: information barrier + .rnd/ and plugin cache auto-allow
│   ├── write-gate.ts            # Write/Edit hook: auto-allows .rnd/ path operations
│   ├── prefer-tools.ts          # Bash hook: blocks sed/cat/grep/find/echo>, auto-allows .rnd/ paths only
│   ├── session-start.ts         # SessionStart hook: injects skill context
│   ├── session-end.ts           # SessionEnd hook: clears active RND session on close/switch
│   ├── post-tool-use.ts         # PostToolUse hook: audit logging, slop analysis, and evidence scanning for Write/Edit
│   ├── slop-gate.ts             # Pure library module: LLM anti-pattern detection (imported by post-tool-use.ts)
│   ├── evidence-warn.ts         # Pure library module: SQL/API reference detection (imported by post-tool-use.ts)
│   ├── observation-mask.ts      # PostToolUse/Bash hook: advises when output exceeds 50 lines
│   ├── injection-scanner.ts     # PostToolUse hook: scans Read/Bash/MCP output for prompt injection patterns
│   ├── stop-failure.ts          # StopFailure hook: logs API errors to stop-failures.jsonl, emits advisory
│   ├── setup.ts                 # Setup hook: validates plugin structure and dependencies
│   ├── instructions-loaded.ts   # InstructionsLoaded hook: reminds to extract project standards
│   ├── pre-compact.ts           # PreCompact hook: saves pipeline state before context compaction
│   ├── post-compact.ts          # PostCompact hook: restores pipeline state after compaction
│   └── statusline.ts            # Statusline script: rate limit usage + pipeline phase (v2.1.80)
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   ├── bump.sh                  # Patch version increment + CHANGELOG entry + git stage
│   ├── validate.ts              # Plugin structure validation (frontmatter, hooks, cross-references)
│   └── extract-patterns.ts      # Deterministic CLAUDE.md rule extraction → project-patterns.json
├── proofs/                      # Lean 4 formal verification of pipeline invariants
└── README.md
```

## Architecture

### Agent Roles and Models

| Agent | Model | Color | Purpose |
|---|---|---|---|
| `rnd-planner` | opus | blue | Decomposes tasks into pre-registered sub-tasks with testable criteria |
| `rnd-builder` | sonnet | green | Implements one task using TDD; produces build manifest + self-assessment |
| `rnd-verifier` | opus | amber | Independent verification — never sees builder reasoning |
| `rnd-integrator` | sonnet | purple | Merges verified outputs, runs integration tests, issues SHIP/NO-SHIP |
| `rnd-data-scientist` | opus | cyan | Standalone specialist for numerical/analytical work, with optional Lean 4 specs |
| `rnd-proof-gate` | sonnet | pink | Attempts formal Lean 4 proofs of pre-registration criteria (advisory) |
| `rnd-debugger` | opus | orange | Reproduces bugs, identifies root causes, and produces a structured diagnosis report for handoff to the Builder |

All agents have `memory: user` (persistent cross-project learning), `skills` preloading (domain-specific skills injected at startup), KISS rules, and `maxTurns` limits to prevent runaway sessions (planner: 250, builder: 200, debugger/integrator/data-scientist: 150, verifier/proof-gate: 100). The verifier additionally has `disallowedTools: Edit` as defense-in-depth (Write is allowed for experiment files in `$RND_DIR` only).

### Information Barrier and Permission Hooks

The `hooks.json` routes each PreToolUse event to an external script. Policies enforced:
- **Information barrier** (`read-gate.ts`): Blocks any `Read` call where the file path contains `self-assessment`, preventing the Verifier from anchoring on Builder reasoning
- **Auto-allow `$RND_DIR` and plugin cache operations** (`read-gate.ts`, `write-gate.ts`, `prefer-tools.ts`): `Read` operations on `.rnd/` paths are auto-allowed. `Write` and `Edit` operations on `.rnd/` paths are auto-allowed. For `Bash`, `.rnd/` paths are auto-allowed only for commands that pass tool discipline checks first (sed/cat/grep/find are still blocked even on `.rnd/` paths). `read-gate.ts` additionally auto-allows reads from the plugin cache (`plugins/cache/`) for skill and agent files
- **Tool discipline** (`prefer-tools.ts`): Blocks `sed`, `cat`, `grep`, `find`, and `echo/printf` with file redirects — enforces use of dedicated Claude Code tools, even for `.rnd/` paths. Splits compound commands (`&&`, `||`, `;`, `|`) and checks each segment, including `$()` and backtick substitutions
- **Commit protection** (`prefer-tools.ts`): Blocks `git add` of `.rnd/` as defense-in-depth; blocks `git push` to main/master/production branches
- **Prompt injection scanning** (`injection-scanner.ts`): PostToolUse hook scans Read/Bash/MCP tool output for common injection patterns (e.g., "ignore previous instructions", `<system>` tags) and emits advisory warnings
- **Audit logging, slop analysis, evidence scanning** (`post-tool-use.ts`): PostToolUse hook logs all Write and Edit operations to `$RND_DIR/audit.jsonl`, analyzes code for LLM anti-patterns, and scans for SQL/API references requiring verification reminders
- **Stop failure logging** (`stop-failure.ts`): StopFailure hook logs API errors (rate limits, auth failures) to `$RND_DIR/stop-failures.jsonl` and emits advisory context

#### Hook Allow/Deny Precedence (v2.1.77+)

As of Claude Code v2.1.77, a PreToolUse hook returning `allow` no longer bypasses explicit deny rules. The effective precedence is:

**deny rules > hook allow > default permission prompt**

This affects the two hooks that auto-allow `.rnd/` operations: `read-gate.ts` and `prefer-tools.ts`. If a user or enterprise policy has a deny rule covering `.rnd/` paths, those hooks' auto-allows will be silently overridden and permission prompts will reappear.

**Workaround:** Use the `allowRead` and `allowWrite` sandbox settings to explicitly re-allow `.rnd/` paths. These settings take precedence over deny rules and restore the intended auto-allow behavior:

```json
{ "allowRead": ["~/.claude/.rnd/**"], "allowWrite": ["~/.claude/.rnd/**"] }
```

### --bare Mode (v2.1.81+)

When Claude Code is launched with `--bare`, all hooks are skipped — SessionStart, read-gate, prefer-tools, post-tool-use, and all others. Practical consequences:

- The information barrier is not enforced: the Verifier can read Builder self-assessments
- Tool discipline is not enforced: sed/cat/grep/find bypass is possible
- Session bootstrap does not run: skills are not injected into context

Bottom line: rnd-framework effectively does not work in `--bare` mode. This is expected — `--bare` is designed for scripted `-p` invocations, not interactive multi-agent orchestration.

### Skill System

Skills are directories under `skills/` containing a `SKILL.md` with YAML frontmatter (`name`, `description`, `effort`). Claude Code's native plugin system discovers skills by directory convention. The `effort` field (added in v2.1.80) overrides the model's reasoning effort when the skill is invoked: `low` for reference/guidance skills, `medium` for procedural workflows. Commands also support `effort` frontmatter: `low` for read-only operations, `medium` for moderate reasoning, `high` for deep multi-agent orchestration.

The `rnd-roadmapping` skill defines the roadmap.md format, milestone statuses, and how agents create and update roadmaps across sessions.

The `rnd-learning` skill enables auto-capture of pipeline-discovered gotchas to the user's Learning Library during iteration cycles.

The `rnd-formatting` skill detects the project's code formatter and runs it on pipeline-changed files before doc-polish and committing.

**Shadowing rule:** Personal skills (in user's `.claude/skills/`) override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

**Plugin freshness (v2.1.81+):** Ref-tracked plugins re-clone on every load, so the cached plugin version is always current. Version mismatch warnings (from `hooks/session-start.ts`) should be rare in v2.1.81+ setups; if they appear, it likely indicates a bug rather than a stale install.

### Session Bootstrap

The `SessionStart` hook fires on `startup|resume|clear|compact` and runs `hooks/session-start.ts`, which reads and injects the `using-rnd-framework` skill content into session context as a system reminder.

The `SessionEnd` hook fires when a session closes or switches (including via `/resume`) and runs `hooks/session-end.ts`, which calls `rnd-dir.sh --finish` to clear the active session marker. This prevents stale `.current-session` files from persisting across sessions.

**Remote pipelines with `--channels` (v2.1.81+):** The `--channels` flag enables permission-relay mode, forwarding tool approval prompts to the Claude mobile app. This is useful when running rnd-framework pipelines on remote or headless machines where interactive terminal input is unavailable.

### Runtime Artifacts

The framework stores artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated artifact space based on a hash of its path. Each pipeline run gets a unique session ID, preserving history across runs.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR` path. Flags: `-c` (create), `--finish` (clear session), `--base` (project base dir), `--roadmap` (path to roadmap.md at project base).

```
~/.claude/.rnd/<basename>-<hash>/          # Project base; slug = git-common-dir basename + 8-char sha256 of canonicalized git-common-dir; falls back to pwd basename + hash when not in a git repo
├── .current-session                       # Active session ID
├── roadmap.md                             # Multi-session roadmap (optional, created by /roadmap)
├── calibration.jsonl                      # Verdict accuracy tracking (legacy; new installs use $CLAUDE_PLUGIN_DATA)
└── sessions/<YYYYMMDD-HHMMSS-XXXX>/      # $RND_DIR (one per pipeline run)
    ├── plan.md                            # Task tree, pre-registrations, schedule
    ├── project-patterns.json              # Project-specific slop patterns extracted from CLAUDE.md
    ├── diagnosis/T*-diagnosis.md          # Debugger root cause analysis (debug pipeline only)
    ├── builds/T*-manifest.md              # Builder output records
    ├── builds/T*-self-assessment.md       # Builder uncertainties (blocked from Verifier)
    ├── verifications/T*-verification.md   # Verifier evidence-based verdicts
    ├── verifications/T*-experiments/      # Verifier-written independent experiment tests
    ├── proofs/T*-proof-report.md          # Proof Gate results (Lean 4 formal verification)
    ├── proofs/T*-theorems/                # Lean theorem files
    ├── integration/wave-*-report.md       # Integration results, SHIP/NO-SHIP
    └── iteration-log.md                   # Build-verify cycle tracking
```

Since `$RND_DIR` is outside the project, no `.gitignore` entry is needed.

**Worktree support:** All worktrees of the same repository share the same `.rnd/` base directory. The project slug is derived from `git rev-parse --git-common-dir` (canonicalized to an absolute path via the POSIX `cd + pwd` idiom), so linked worktrees and the main checkout produce identical slugs even though their `pwd` values differ.

## Commands

Slash commands use the full plugin namespace: `/rnd-framework:start`, `/rnd-framework:plan`, `/rnd-framework:build`, `/rnd-framework:verify`, `/rnd-framework:integrate`, `/rnd-framework:status`, `/rnd-framework:resume`, `/rnd-framework:quick`, `/rnd-framework:history`, `/rnd-framework:validate`, `/rnd-framework:doctor`, `/rnd-framework:bump`, `/rnd-framework:review`, `/rnd-framework:audit`, `/rnd-framework:brainstorm`, `/rnd-framework:narrative`, `/rnd-framework:calibrate`, `/rnd-framework:debug`, `/rnd-framework:roadmap`.

## Key Conventions

- **Skills use YAML frontmatter** — `name`, `description`, and `effort` fields between `---` delimiters
- **Commands are Markdown files** in `commands/` — filename becomes the command name
- **Agents are Markdown files** in `agents/` — YAML frontmatter specifies `model`, `tools`, `memory`, `color`, `skills`, and optionally `disallowedTools`, `maxTurns`
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`
- **Test suite** — `tests/` contains Bun tests for hooks and lib scripts; run with `bun test` from `plugins/rnd-framework/`
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools`), then Bun scripts (`bun-scripting`), then Python as last resort
- **File creation** — always use `Write`/`Edit` tools, never bash heredocs (`cat > file << 'EOF'`)

## Working on This Codebase

When modifying skills, agents, or commands, the content is Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new Claude Code session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
