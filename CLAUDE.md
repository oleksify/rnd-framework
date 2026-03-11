# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing the **rnd-framework** — a scientific-method orchestration system for multi-agent coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.

The plugin lives at `plugins/rnd-framework/`. The root `.claude-plugin/marketplace.json` is a local plugin registry that references it.

## Repository Layout

```
plugins/rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
├── agents/                      # 5 specialized agents (planner, builder, verifier, integrator, data-scientist)
├── commands/                    # 11 slash commands (/rnd-framework:start, etc.)
├── skills/                      # 17 skills, each in its own dir with SKILL.md
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── hooks/
│   ├── hooks.json               # SessionStart bootstrap + PreToolUse + PostToolUse hook routing
│   ├── auto-allow-rnd           # Write/Edit hook: auto-allows .rnd/ paths
│   ├── read-gate                # Read hook: information barrier + .rnd/ auto-allow
│   ├── prefer-tools             # Bash hook: blocks sed/cat/grep/find/echo>, auto-allows ls/.rnd
│   ├── session-start            # SessionStart hook: injects skill context via jq
│   └── audit-log                # PostToolUse hook: logs Write/Edit operations to audit.jsonl
├── lib/
│   ├── rnd-dir.sh               # Artifact directory path computation + session management
│   └── bump.sh                  # Patch version increment + CHANGELOG entry + git stage
└── README.md
```

## Architecture

### Agent Roles and Models

| Agent | Model | Purpose |
|---|---|---|
| `rnd-planner` | opus | Decomposes tasks into pre-registered sub-tasks with testable criteria |
| `rnd-builder` | sonnet | Implements one task using TDD; produces build manifest + self-assessment |
| `rnd-verifier` | opus | Independent verification — never sees builder reasoning |
| `rnd-integrator` | sonnet | Merges verified outputs, runs integration tests, issues SHIP/NO-SHIP |
| `rnd-data-scientist` | opus | Standalone specialist for numerical/analytical work — finances, calculations, data, analytics, charts, insights; uses Julia or DuckDB CLI as computation backend |

### Information Barrier and Permission Hooks

The `hooks.json` routes each PreToolUse event to an external script. Policies enforced:
- **Information barrier** (`read-gate`): Blocks any `Read` call where the file path contains `self-assessment`, preventing the Verifier from anchoring on Builder reasoning
- **Auto-allow `$RND_DIR` operations** (`auto-allow-rnd`, `read-gate`, `prefer-tools`): All `Read`, `Write`, `Edit`, and `Bash` operations targeting paths containing `.rnd/` are auto-allowed (no permission prompts), except self-assessment reads
- **Tool discipline** (`prefer-tools`): Blocks `sed`, `cat`, `grep`, `find`, and `echo/printf` with file redirects — enforces use of dedicated Claude Code tools
- **Commit protection** (`prefer-tools`): Blocks `git add` of `.rnd/` as defense-in-depth
- **Audit logging** (`audit-log`): PostToolUse hook logs all Write and Edit operations to `$RND_DIR/audit.jsonl` during active pipeline sessions

### Skill System

Skills are directories under `skills/` containing a `SKILL.md` with YAML frontmatter (`name`, `description`). Claude Code's native plugin system discovers skills by directory convention.

**Shadowing rule:** Personal skills (in user's `.claude/skills/`) override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

### Session Bootstrap

The `SessionStart` hook fires on `startup|resume|clear|compact` and runs `hooks/session-start`, which reads and injects the `using-rnd-framework` skill content into session context as a system reminder.

### Runtime Artifacts

The framework stores artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated artifact space based on a hash of its path. Each pipeline run gets a unique session ID, preserving history across runs.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR` path. Flags: `-c` (create), `--finish` (clear session), `--base` (project base dir).

```
~/.claude/.rnd/<dirname>-<hash>/           # Project base
├── .current-session                       # Active session ID
└── sessions/<YYYYMMDD-HHMMSS-XXXX>/      # $RND_DIR (one per pipeline run)
    ├── plan.md                            # Task tree, pre-registrations, schedule
    ├── builds/T*-manifest.md              # Builder output records
    ├── builds/T*-self-assessment.md       # Builder uncertainties (blocked from Verifier)
    ├── verifications/T*-verification.md   # Verifier evidence-based verdicts
    ├── integration/wave-*-report.md       # Integration results, SHIP/NO-SHIP
    └── iteration-log.md                   # Build-verify cycle tracking
```

Since `$RND_DIR` is outside the project, no `.gitignore` entry is needed.

## Commands

Slash commands use the full plugin namespace: `/rnd-framework:start`, `/rnd-framework:plan`, `/rnd-framework:build`, `/rnd-framework:verify`, `/rnd-framework:integrate`, `/rnd-framework:status`, `/rnd-framework:quick`, `/rnd-framework:history`, `/rnd-framework:validate`, `/rnd-framework:doctor`, `/rnd-framework:bump`.

## Key Conventions

- **Skills use YAML frontmatter** — `name` and `description` fields between `---` delimiters
- **Commands are Markdown files** in `commands/` — filename becomes the command name
- **Agents are Markdown files** in `agents/` — YAML frontmatter specifies `model`, tools list
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`
- **Test suite** — `tests/` contains Bun tests for hooks and lib scripts; run with `bun test` from `plugins/rnd-framework/`
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools`), then Bun scripts (`bun-scripting`), then Python as last resort
- **File creation** — always use `Write`/`Edit` tools, never bash heredocs (`cat > file << 'EOF'`)

## Working on This Codebase

When modifying skills, agents, or commands, the content is Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new Claude Code session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
