# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing the **rnd-framework** — a scientific-method orchestration system for multi-agent coding. It structures workflows around pre-registration, independent verification with information barriers, evidence-based quality gates, and structured decomposition.

The plugin lives at `plugins/rnd-framework/`. The root `.claude-plugin/marketplace.json` is a local plugin registry that references it.

## Repository Layout

```
plugins/rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
├── agents/                      # 4 specialized agents (planner, builder, verifier, integrator)
├── commands/                    # 8 slash commands (/rnd-framework:start, etc.)
├── skills/                      # 16 skills, each in its own dir with SKILL.md
├── output-styles/               # 3 custom output styles (scientific, rigorous, pipeline)
├── hooks/
│   ├── hooks.json               # SessionStart bootstrap + PreToolUse hooks
│   ├── prefer-tools             # Bash hook: blocks sed/cat/grep/find, auto-allows ls/.rnd
│   └── session-start            # Bash script injecting using-rnd-framework skill into context
├── lib/
│   └── rnd-dir.sh               # Artifact directory path computation + session management
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

### Information Barrier and Permission Hooks

The `hooks.json` PreToolUse hooks enforce several policies:
- **Information barrier:** Blocks any `Read` call where the file path contains `self-assessment`, preventing the Verifier from anchoring on Builder reasoning
- **Commit protection:** Blocks `git add` of `.rnd/` as defense-in-depth (artifacts live outside the project in `$RND_DIR`, so this is a safety net)
- **Auto-allow `$RND_DIR` operations:** All `Read`, `Write`, `Edit`, and `Bash` operations targeting paths containing `.rnd/` are auto-allowed (no permission prompts), except self-assessment reads

### Skill System

Skills are directories under `skills/` containing a `SKILL.md` with YAML frontmatter (`name`, `description`). Claude Code's native plugin system discovers skills by directory convention.

**Shadowing rule:** Personal skills (in user's `.claude/skills/`) override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

### Session Bootstrap

The `SessionStart` hook fires on `startup|resume|clear|compact` and runs `hooks/session-start`, which reads and injects the `using-rnd-framework` skill content into session context as a system reminder.

### Runtime Artifacts

The framework stores artifacts in a centralized directory outside the project tree, computed by `lib/rnd-dir.sh`. Each project gets an isolated artifact space based on a hash of its path. Each pipeline run gets a unique session ID, preserving history across runs.

**Helper:** `"${CLAUDE_PLUGIN_ROOT}/lib/rnd-dir.sh"` — outputs absolute `$RND_DIR` path. Flags: `-c` (create), `--finish` (clear session), `--base` (project base dir).

```
~/.claude/.rnd/project-<hash>/             # Project base
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

Slash commands use the full plugin namespace: `/rnd-framework:start`, `/rnd-framework:plan`, `/rnd-framework:build`, `/rnd-framework:verify`, `/rnd-framework:integrate`, `/rnd-framework:status`, `/rnd-framework:quick`, `/rnd-framework:history`.

## Key Conventions

- **Skills use YAML frontmatter** — `name` and `description` fields between `---` delimiters
- **Commands are Markdown files** in `commands/` — filename becomes the command name
- **Agents are Markdown files** in `agents/` — YAML frontmatter specifies `model`, tools list
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`
- **No test suite** — verification happens through the pipeline itself (build manifests + verification reports)
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools`), then Bun scripts (`bun-scripting`), then Python as last resort
- **File creation** — always use `Write`/`Edit` tools, never bash heredocs (`cat > file << 'EOF'`)

## Working on This Codebase

When modifying skills, agents, or commands, the content is Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new Claude Code session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
