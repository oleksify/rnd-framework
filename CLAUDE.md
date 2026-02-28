# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin repository containing the **rnd-framework** — an R&D-inspired multi-agent orchestration system. It structures coding workflows around structured decomposition, dependency-based scheduling, independent verification with information barriers, quality gates, and spec-first accountability.

The plugin lives at `plugins/rnd-framework/`. The root `.claude-plugin/marketplace.json` is a local plugin registry that references it.

## Repository Layout

```
plugins/rnd-framework/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, description)
├── agents/                      # 4 specialized agents (planner, builder, verifier, integrator)
├── commands/                    # 7 slash commands (/rnd-framework:start, etc.)
├── skills/                      # 15 skills, each in its own dir with SKILL.md
├── hooks/
│   ├── hooks.json               # SessionStart bootstrap + PreToolUse information barrier
│   └── session-start            # Bash script injecting using-rnd-framework skill into context
├── lib/skills-core.js           # Skill discovery, resolution, frontmatter parsing (ESM)
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
- **Information barrier:** Blocks any `Read` call where `TOOL_INPUT` contains `self-assessment`, preventing the Verifier from anchoring on Builder reasoning
- **Commit protection:** Blocks `git add` of `.rnd/` — pipeline artifacts must never be committed
- **Auto-allow `.rnd/` operations:** All `Read`, `Write`, `Edit`, and `Bash` operations targeting `.rnd/` are auto-allowed (no permission prompts), except self-assessment reads and git-add

### Skill System

Skills are directories under `skills/` containing a `SKILL.md` with YAML frontmatter (`name`, `description`). Discovery uses `lib/skills-core.js` which recursively searches up to depth 3.

**Shadowing rule:** Personal skills (in user's `.claude/skills/`) override rnd-framework skills unless explicitly prefixed with `rnd-framework:`.

### Session Bootstrap

The `SessionStart` hook fires on `startup|resume|clear|compact` and runs `hooks/session-start`, which reads and injects the `using-rnd-framework` skill content into session context as a system reminder.

### Runtime Artifacts

The framework creates `.rnd/` in the working directory during pipeline execution:

```
.rnd/
├── plan.md                    # Task tree, pre-registrations, schedule
├── builds/T*-manifest.md      # Builder output records
├── builds/T*-self-assessment.md  # Builder uncertainties (blocked from Verifier)
├── verifications/T*-verification.md  # Verifier evidence-based verdicts
├── integration/wave-*-report.md      # Integration results, SHIP/NO-SHIP
└── iteration-log.md           # Build-verify cycle tracking
```

## Commands

Slash commands use the full plugin namespace: `/rnd-framework:start`, `/rnd-framework:plan`, `/rnd-framework:build`, `/rnd-framework:verify`, `/rnd-framework:integrate`, `/rnd-framework:status`, `/rnd-framework:quick`.

## Key Conventions

- **Skills use YAML frontmatter** — `name` and `description` fields between `---` delimiters
- **Commands are Markdown files** in `commands/` — filename becomes the command name
- **Agents are Markdown files** in `agents/` — YAML frontmatter specifies `model`, tools list
- **Plugin manifest** at `.claude-plugin/plugin.json` — only `name`, `description`, `version`
- **ESM modules** — `lib/skills-core.js` uses `import`/`export` syntax
- **No test suite** — verification happens through the pipeline itself (build manifests + verification reports)
- **Tooling hierarchy** — system CLI tools first (`prefer-system-tools`), then Bun scripts (`bun-scripting`), then Python as last resort
- **File creation** — always use `Write`/`Edit` tools, never bash heredocs (`cat > file << 'EOF'`)

## Working on This Codebase

When modifying skills, agents, or commands, the content is Markdown processed by Claude Code's plugin system. Changes take effect in new sessions.

To test a hook change, start a new Claude Code session in a project with this plugin enabled.

To verify plugin registration: check that `.claude-plugin/marketplace.json` lists the plugin and the source path resolves to a valid `plugin.json`.
